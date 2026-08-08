//// embed — the embedding seam. Turns text into a fixed-dim vector for
//// aarondb's vec_index (HNSW). bankai's vector features (dedup, memory RAG,
//// semantic search) call `embed` here and nothing else.
////
//// Default backend: the signed hashing trick over lowercased tokens —
//// dependency-free (pure Gleam + aarondb/vector.normalize), deterministic,
//// produces LEXICAL-similarity vectors (catches near-duplicate wording, not
//// synonyms). To get true semantic similarity, swap this single module's
//// `embed` for an OpenAI/ollama-backed one; nothing else in bankai changes.

import aarondb/vector
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/order.{Gt, Lt}
import gleam/string

/// Vector dimensionality for the default term-hash backend.
pub const dims = 256

/// The default backend's name (surfaced in CLI/help so the lexical limitation
/// is honest, not hidden).
pub const backend = "term-hash (lexical)"

/// Embed text into a 256-dim L2-normalized vector (signed hashing trick).
/// Deterministic, no model. This is the seam — replace it for real embeddings.
pub fn embed(text: String) -> List(Float) {
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
