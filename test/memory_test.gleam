import bankai/cli
import bankai/memory
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleamunison/identity
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

/// Test isolation: empty the workspace's data files before each test.
/// (gleeunit has no global setup hook.)
fn wipe(ws: String) {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  Nil
}

/// G9: unwrap a {"ok": <memory>} envelope into the Memory.
fn ok_memory_decoder() -> decode.Decoder(memory.Memory) {
  use m <- decode.field("ok", memory.memory_decoder())
  decode.success(m)
}

fn memory_from_output(
  output: String,
) -> Result(memory.Memory, json.DecodeError) {
  json.parse(from: output, using: ok_memory_decoder())
}

pub fn memory_is_content_addressed_test() {
  let m1 = memory.new("hello", 1000)
  let m2 = memory.new("hello", 1000)
  identity.hash_equal(m1.content_hash, m2.content_hash)
  |> should.be_true
  let m3 = memory.new("hello", 1001)
  identity.hash_equal(m1.content_hash, m3.content_hash)
  |> should.be_false
}

pub fn remember_creates_and_persists_test() {
  let ws = "/tmp/bankai_memory_remember"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let out = cli.run_in(ws, ["remember", "Always run tests before commit"])

  let mem = should.be_ok(memory_from_output(out))
  mem.text |> should.equal("Always run tests before commit")

  // persisted across a reload (JSONL round-trip)
  cli.run_in(ws, ["memories"])
  |> string.contains("Always run tests before commit")
  |> should.be_true
}

pub fn prime_injects_memories_test() {
  let ws = "/tmp/bankai_memory_prime"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["remember", "Prefer Babashka for scripting"])

  let prime = cli.run_in(ws, ["prime"])
  prime |> string.contains("Prefer Babashka for scripting") |> should.be_true
  prime |> string.contains("Agent memories") |> should.be_true
}

pub fn prime_without_memories_is_base_prompt_test() {
  let ws = "/tmp/bankai_memory_nopmem"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let prime = cli.run_in(ws, ["prime"])
  // no memories -> base prompt, no memories section
  prime |> string.contains("Agent memories") |> should.be_false
}

pub fn remember_rejects_empty_text_test() {
  let ws = "/tmp/bankai_memory_empty"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["remember", ""])
  |> string.contains("must not be empty")
  |> should.be_true
}

/// bk-018b: remembering identical text is idempotent — one entry, existing
/// memory returned, not a second copy.
pub fn remember_dedupes_identical_text_test() {
  let ws = "/tmp/bankai_memory_dedupe"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["remember", "Prefer Babashka over Python"])

  let second =
    should.be_ok(
      memory_from_output(
        cli.run_in(ws, ["remember", "Prefer Babashka over Python"]),
      ),
    )

  // second remember returns the FIRST memory, not a new one
  memory.all(ws) |> should.be_ok
  let assert Ok(all) = memory.all(ws)
  all
  |> list.filter(fn(m) { m.text == "Prefer Babashka over Python" })
  |> list.length
  |> should.equal(1)
  let _ = second
  Nil
}

/// bk-d3be: search results carry the hit text — memories become recallable.
pub fn search_includes_memory_text_test() {
  let ws = "/tmp/bankai_memory_search_text"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["remember", "run smoke tests before deploy"])

  let out = cli.run_in(ws, ["search", "smoke"])

  // the memory hit carries its text, not just an opaque hash id
  out
  |> string.contains("run smoke tests before deploy")
  |> should.be_true
}
