import bankai/builder
import bankai/memory
import bankai/message
import bankai/serde
import bankai/types.{Open}
import gleam/option
import gleam/string
import gleamunison/identity
import gleeunit/should

fn replace_hash(
  encoded: String,
  hash: identity.Hash,
  replacement: String,
) -> String {
  string.replace(encoded, identity.hash_to_debug_string(hash), replacement)
}

pub fn task_json_rejects_malformed_content_hash_test() {
  let task =
    builder.build(
      "bk-hash",
      "Hash decoding",
      "Reject malformed external references",
      Open,
      option.None,
      1,
      1000,
      1000,
      [],
    )
  let encoded =
    serde.task_to_json_string(task)
    |> replace_hash(task.content_hash, "not-a-hash")

  serde.task_from_json_string(encoded)
  |> should.equal(Error("task decode failed"))
}

pub fn memory_json_rejects_non_hex_content_hash_test() {
  let mem = memory.new("remember validated hashes", 1000)
  let encoded =
    memory.memory_to_json_string(mem)
    |> replace_hash(mem.content_hash, string.repeat("z", 64))

  memory.memory_from_json_string(encoded)
  |> should.equal(Error("memory decode failed"))
}

pub fn message_json_rejects_short_content_hash_test() {
  let msg = message.new("bk-hash", "", "test", "validate hashes", 1000)
  let encoded =
    message.message_to_json_string(msg)
    |> replace_hash(msg.content_hash, string.repeat("a", 63))

  message.message_from_json_string(encoded)
  |> should.equal(Error("message decode failed"))
}
