//// Agent memories (G4) — short content-addressed insights that persist across
//// runs and are injected into `prime` output so agents start with context.
////
//// A memory is content-addressed like a task: SHA-256 over canonical bytes
//// (text + created_at; content_hash excluded, just like Task). Lives in
//// .bankai/memories.jsonl alongside tasks.jsonl.

import bankai/time
import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleamunison/identity
import simplifile

pub type Memory {
  Memory(text: String, created_at: Int, content_hash: identity.Hash)
}

/// Canonical, deterministic byte encoding (versioned — see canonical.gleam).
/// Excludes content_hash (a hash cannot include itself).
pub fn memory_bytes(m: Memory) -> BitArray {
  let text_b = bit_array.from_string(m.text)
  let created_b = bit_array.from_string(int.to_string(m.created_at))
  <<
    1,
    bit_array.byte_size(text_b):size(32),
    text_b:bits,
    bit_array.byte_size(created_b):size(32),
    created_b:bits,
  >>
}

pub fn memory_hash(m: Memory) -> identity.Hash {
  identity.hash_bytes(memory_bytes(m))
}

/// Build a memory with a real content hash (computed from a placeholder draft,
/// mirroring builder.build_with_derived_id — no self-reference).
pub fn new(text: String, created_at: Int) -> Memory {
  let draft =
    Memory(text:, created_at:, content_hash: identity.hash_bytes(<<>>))
  Memory(..draft, content_hash: memory_hash(draft))
}

// --- JSON ---

pub fn memory_to_json(m: Memory) -> json.Json {
  json.object([
    #("text", json.string(m.text)),
    #("created_at", json.int(m.created_at)),
    #(
      "content_hash",
      json.string(identity.hash_to_debug_string(m.content_hash)),
    ),
  ])
}

pub fn memory_to_json_string(m: Memory) -> String {
  json.to_string(memory_to_json(m))
}

pub fn memory_decoder() -> decode.Decoder(Memory) {
  use text <- decode.field("text", decode.string)
  use created_at <- decode.field("created_at", decode.int)
  use hash_hex <- decode.field("content_hash", decode.string)
  decode.success(Memory(
    text:,
    created_at:,
    content_hash: identity.hash_from_bytes(identity.hex_to_bytes(hash_hex)),
  ))
}

pub fn memory_from_json_string(s: String) -> Result(Memory, String) {
  case json.parse(from: s, using: memory_decoder()) {
    Ok(m) -> Ok(m)
    Error(_) -> Error("memory decode failed")
  }
}

// --- JSONL persistence ---

pub fn flush(
  memories: List(Memory),
  to path: String,
) -> Result(Nil, simplifile.FileError) {
  let body =
    memories
    |> list.map(memory_to_json)
    |> list.map(json.to_string)
    |> string.join("\n")
  // BUG-09: trailing newline for wc -l / jq interop.
  let body = case list.is_empty(memories) {
    True -> ""
    False -> body <> "\n"
  }
  simplifile.write(body, to: path)
}

pub fn load(from path: String) -> Result(List(Memory), String) {
  case simplifile.read(from: path) {
    Ok(body) ->
      case body {
        "" -> Ok([])
        _ ->
          body
          |> string.split("\n")
          |> list.filter(fn(line) { line != "" })
          |> list.try_map(memory_from_json_string)
      }
    // Missing file / unreadable = empty memory set (never crash the CLI).
    Error(_) -> Ok([])
  }
}
