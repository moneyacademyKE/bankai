//// Task-scoped threaded messages (Phase C).
////
//// A Message is content-addressed like a Task or Memory: SHA-256 over
//// canonical bytes (task_id + parent_msg_id + author + text + ts;
//// content_hash excluded, a hash cannot include itself). Stored in
//// .bankai/messages.jsonl alongside tasks.jsonl.
////
//// Threading: parent_msg_id points to the parent message (or empty
//// string for top-level messages under a task). The CLI renders
//// threaded lists by walking the parent chain.

import gleam/bit_array
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import gleamunison/identity
import simplifile

pub type Message {
  Message(
    id: String,
    task_id: String,
    parent_msg_id: String,
    author: String,
    text: String,
    ts: Int,
    content_hash: identity.Hash,
  )
}

/// Canonical, deterministic byte encoding (versioned).
/// Excludes content_hash (a hash cannot include itself).
pub fn message_bytes(m: Message) -> BitArray {
  let task_b = bit_array.from_string(m.task_id)
  let parent_b = bit_array.from_string(m.parent_msg_id)
  let author_b = bit_array.from_string(m.author)
  let text_b = bit_array.from_string(m.text)
  let ts_b = bit_array.from_string(int.to_string(m.ts))
  <<
    1,
    bit_array.byte_size(task_b):size(32),
    task_b:bits,
    bit_array.byte_size(parent_b):size(32),
    parent_b:bits,
    bit_array.byte_size(author_b):size(32),
    author_b:bits,
    bit_array.byte_size(text_b):size(32),
    text_b:bits,
    bit_array.byte_size(ts_b):size(32),
    ts_b:bits,
  >>
}

pub fn message_hash(m: Message) -> identity.Hash {
  identity.hash_bytes(message_bytes(m))
}

/// Build a message with a real content hash.
pub fn new(
  task_id: String,
  parent_msg_id: String,
  author: String,
  text: String,
  ts: Int,
) -> Message {
  let draft =
    Message(
      id: "",
      task_id:,
      parent_msg_id:,
      author:,
      text:,
      ts:,
      content_hash: identity.hash_bytes(<<>>),
    )
  Message(..draft, id: short_id(draft), content_hash: message_hash(draft))
}

/// Short id derived from the content hash: "msg-" + first 6 hex chars.
fn short_id(m: Message) -> String {
  "msg-" <> string.slice(identity.hash_to_debug_string(m.content_hash), 0, 6)
}

// --- JSON ---

pub fn message_to_json(m: Message) -> json.Json {
  json.object([
    #("id", json.string(m.id)),
    #("task_id", json.string(m.task_id)),
    #("parent_msg_id", json.string(m.parent_msg_id)),
    #("author", json.string(m.author)),
    #("text", json.string(m.text)),
    #("ts", json.int(m.ts)),
    #(
      "content_hash",
      json.string(identity.hash_to_debug_string(m.content_hash)),
    ),
  ])
}

pub fn message_to_json_string(m: Message) -> String {
  json.to_string(message_to_json(m))
}

pub fn message_decoder() -> decode.Decoder(Message) {
  use id <- decode.field("id", decode.string)
  use task_id <- decode.field("task_id", decode.string)
  use parent_msg_id <- decode.field("parent_msg_id", decode.string)
  use author <- decode.field("author", decode.string)
  use text <- decode.field("text", decode.string)
  use ts <- decode.field("ts", decode.int)
  use hash_hex <- decode.field("content_hash", decode.string)
  decode.success(Message(
    id:,
    task_id:,
    parent_msg_id:,
    author:,
    text:,
    ts:,
    content_hash: identity.hash_from_bytes(identity.hex_to_bytes(hash_hex)),
  ))
}

pub fn message_from_json_string(s: String) -> Result(Message, String) {
  case json.parse(from: s, using: message_decoder()) {
    Ok(m) -> Ok(m)
    Error(_) -> Error("message decode failed")
  }
}

// --- JSONL persistence ---

pub fn flush(
  messages: List(Message),
  to path: String,
) -> Result(Nil, simplifile.FileError) {
  let body =
    messages
    |> list.map(message_to_json)
    |> list.map(json.to_string)
    |> string.join("\n")
  let body = case list.is_empty(messages) {
    True -> ""
    False -> body <> "\n"
  }
  simplifile.write(body, to: path)
}

pub fn load(from path: String) -> Result(List(Message), String) {
  case simplifile.read(from: path) {
    Ok(body) ->
      case body {
        "" -> Ok([])
        _ ->
          body
          |> string.split("\n")
          |> list.filter(fn(line) { line != "" })
          |> list.try_map(message_from_json_string)
      }
    Error(_) -> Ok([])
  }
}
