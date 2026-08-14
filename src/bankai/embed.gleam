//// embed — the embedding seam. Turns text into an L2-normalized vector for
//// aarondb's vec_index (HNSW). bankai's vector features (dedup, memory RAG,
//// semantic search) call `embed` here and nothing else.
////
//// Backends: a local ollama /api/embed endpoint (true semantic similarity)
//// or a dependency-free signed-hashing-trick term-hash (lexical similarity
//// only — catches overlapping terminology, not synonyms). Resolution is
//// sticky for the life of the process because a single HNSW index build
//// must never mix vector dimensionalities from two backends.
////
//// Configure: BANKAI_EMBED_BACKEND (auto|ollama|term-hash, default auto),
//// BANKAI_OLLAMA_URL (default http://127.0.0.1:11434), BANKAI_EMBED_MODEL
//// (default nomic-embed-text). `auto` and `ollama` prefer a reachable
//// ollama and degrade to term-hash when it is not; `term-hash` skips the
//// probe entirely.

import aarondb/vector
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/result
import gleam/string

/// Vector dimensionality of the term-hash fallback backend.
pub const dims = 256

/// The fallback backend's name (surfaced in CLI/help so the lexical
/// limitation is honest, not hidden).
pub const backend = "term-hash (lexical)"

/// The resolved embedding backend.
pub type Backend {
  /// A reachable local ollama endpoint: base url, model, observed dims.
  Ollama(url: String, model: String, dims: Int)
  /// Deterministic signed-hashing-trick backend. Lexical, no model, total.
  TermHash
}

@external(erlang, "bankai_embed_ffi", "embed_remote")
fn ffi_embed_remote(
  text: String,
  url: String,
  model: String,
  timeout_ms: Int,
) -> Result(List(Float), String)

@external(erlang, "bankai_embed_ffi", "probe")
fn ffi_probe(url: String, model: String) -> Result(Int, String)

@external(erlang, "bankai_embed_ffi", "sticky_get")
fn ffi_sticky_get(key: String) -> Result(Backend, Nil)

@external(erlang, "bankai_embed_ffi", "sticky_put")
fn ffi_sticky_put(key: String, value: Backend) -> Nil

@external(erlang, "bankai_embed_ffi", "sticky_clear")
pub fn reset_resolution() -> Nil

@external(erlang, "bankai_embed_ffi", "getenv")
fn ffi_getenv(name: String) -> Result(String, Nil)

const sticky_key = "bankai_embed_backend_v1"

const default_url = "http://127.0.0.1:11434"

const default_model = "nomic-embed-text"

const embed_timeout_ms = 10_000

/// Embed text into an L2-normalized vector. This is the seam — everything in
/// bankai calls only this function. Total under term-hash; under a resolved
/// ollama backend it panics if the endpoint dies mid-run so callers surface
/// the failure honestly instead of silently mixing dimensionalities.
pub fn embed(text: String) -> List(Float) {
  case resolve() {
    TermHash -> term_hash(text)
    Ollama(url, model, _) ->
      case ffi_embed_remote(text, url, model, embed_timeout_ms) {
        Ok(vec) -> vector.normalize(vec)
        Error(reason) ->
          panic as {
            "embedding backend unavailable ("
            <> reason
            <> "); restore ollama or restart with BANKAI_EMBED_BACKEND=term-hash"
          }
      }
  }
}

/// The active backend's honest name, e.g. "ollama/nomic-embed-text (semantic)"
/// or "term-hash (lexical)". Surfaced through doctor so the retrieval story
/// stays honest.
pub fn active_backend() -> String {
  case resolve() {
    Ollama(_, model, _) -> "ollama/" <> model <> " (semantic)"
    TermHash -> backend
  }
}

/// Resolve the backend once per process (sticky via persistent_term, which
/// is VM-global): env mode, one reachability probe, then cached forever.
pub fn resolve() -> Backend {
  case ffi_sticky_get(sticky_key) {
    Ok(resolved) -> resolved
    Error(Nil) -> {
      let mode = getenv_or("BANKAI_EMBED_BACKEND", "auto")
      let url = getenv_or("BANKAI_OLLAMA_URL", default_url)
      let model = getenv_or("BANKAI_EMBED_MODEL", default_model)
      let probe = case mode {
        "term-hash" -> Error(Nil)
        _ -> result.replace_error(ffi_probe(url, model), Nil)
      }
      let resolved = resolve_from(mode, url, model, probe)
      ffi_sticky_put(sticky_key, resolved)
      resolved
    }
  }
}

/// Pure decision core, public for tests: mode + probe outcome -> backend.
/// ollama wins only when the probe succeeded; every failure degrades to the
/// total term-hash backend.
pub fn resolve_from(
  mode: String,
  url: String,
  model: String,
  probe: Result(Int, Nil),
) -> Backend {
  case mode, probe {
    "term-hash", _ -> TermHash
    _, Ok(observed_dims) -> Ollama(url, model, observed_dims)
    _, Error(Nil) -> TermHash
  }
}

fn getenv_or(name: String, fallback: String) -> String {
  case ffi_getenv(name) {
    Ok(value) -> value
    Error(Nil) -> fallback
  }
}

// ---------------------------------------------------------------------------
// term-hash backend — unchanged pure Gleam (signed hashing trick).
// ---------------------------------------------------------------------------

/// Embed text into a 256-dim L2-normalized vector (signed hashing trick).
/// Deterministic, no model. Lexical similarity only.
pub fn term_hash(text: String) -> List(Float) {
  text
  |> tokenize
  |> list.fold(initial_vector(), accumulate)
  |> vector.normalize
}

fn initial_vector() -> List(Float) {
  list.repeat(0.0, dims)
}

fn accumulate(vec: List(Float), token: String) -> List(Float) {
  let h = hash(token)
  let assert Ok(dim) = int.modulo(h, dims)
  let sign = case int.modulo(h, 2) {
    Ok(0) -> 1.0
    _ -> -1.0
  }
  list.index_map(vec, fn(v, i) {
    case i == dim {
      True -> v +. sign
      False -> v
    }
  })
}

/// Lowercase, split on whitespace, strip punctuation, drop empties.
fn tokenize(text: String) -> List(String) {
  text
  |> string.lowercase
  |> string.split(" ")
  |> list.flat_map(fn(t) { string.split(t, "\n") })
  |> list.map(string.trim)
  |> list.map(strip_punct)
  |> list.filter(fn(t) { t != "" })
}

fn strip_punct(s: String) -> String {
  s
  |> string.to_graphemes
  |> list.filter(is_alnum)
  |> string.join(with: "")
}

fn is_alnum(g: String) -> Bool {
  let in_az = string.compare(g, "a") != Lt && string.compare(g, "z") != Gt
  let in_09 = string.compare(g, "0") != Lt && string.compare(g, "9") != Gt
  in_az || in_09
}

/// djb2 string hash over UTF-8 bytes — deterministic, pure Gleam, no deps.
fn hash(token: String) -> Int {
  bit_array.from_string(token)
  |> fold_bytes(5381)
}

fn fold_bytes(binary: BitArray, acc: Int) -> Int {
  case binary {
    <<>> -> acc
    <<byte:size(8), rest:bytes>> -> fold_bytes(rest, acc * 33 + byte)
    _ -> acc
  }
}
