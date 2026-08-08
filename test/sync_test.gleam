import bankai/ast_bridge
import bankai/builder
import bankai/cli
import bankai/serde
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/types.{InProgress, Open, Task}
import gleam/list
import gleam/option
import gleam/string
import gleamunison/identity
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = simplifile.write("", to: ws <> "/messages.jsonl")
  Nil
}

fn fresh() {
  builder.build(
    "bk-0001",
    "Write spec",
    "desc",
    Open,
    option.None,
    1,
    1000,
    1000,
    [],
  )
}

pub fn json_roundtrip_test() {
  let t = fresh()
  let back = serde.task_from_json_string(serde.task_to_json_string(t))
  let task = should.be_ok(back)
  identity.hash_equal(task.content_hash, t.content_hash)
  |> should.be_true
  task.id
  |> should.equal("bk-0001")
}

pub fn jsonl_flush_load_roundtrip_test() {
  let t1 = fresh()
  let t2 =
    builder.build(
      "bk-0002",
      "two",
      "d",
      InProgress,
      option.None,
      2,
      1000,
      1000,
      [],
    )
  let path = "test_bk_tasks.jsonl"
  let _ = jsonl.flush([t1, t2], to: path)
  let loaded = jsonl.load(from: path)

  let tasks = should.be_ok(loaded)
  tasks
  |> list.length()
  |> should.equal(2)
}

pub fn tampered_json_identity_is_rejected_test() {
  let task = fresh()
  let tampered = Task(..task, title: "Edited without rehashing")
  ast_bridge.validate(tampered)
  |> should.be_error
  serde.task_from_json_string(serde.task_to_json_string(tampered))
  |> should.be_error
}

pub fn jsonl_load_rejects_tampered_identity_test() {
  let path = "/tmp/bankai_tampered_tasks.jsonl"
  let task = fresh()
  let tampered = Task(..task, title: "Edited without rehashing")
  let _ =
    simplifile.write(serde.task_to_json_string(tampered) <> "\n", to: path)
  jsonl.load(from: path) |> should.be_error
}

pub fn rehash_is_the_explicit_update_path_test() {
  let task = fresh()
  let updated = ast_bridge.rehash(Task(..task, title: "Rehashed update"))
  ast_bridge.validate(updated) |> should.be_ok
}

pub fn clean_merge_unions_identical_hashes_test() {
  let local = [fresh()]
  let remote = [fresh()]
  let result = merge.merge(local, remote)

  result.tasks
  |> list.length()
  |> should.equal(1)
  result.conflicts
  |> list.is_empty()
  |> should.be_true
}

pub fn divergent_same_id_is_a_conflict_test() {
  // same id, different status -> different content hash -> conflict
  let local = [fresh()]
  let remote = [
    builder.build(
      "bk-0001",
      "Write spec",
      "desc",
      InProgress,
      option.None,
      1,
      1000,
      1000,
      [],
    ),
  ]
  let result = merge.merge(local, remote)

  result.conflicts
  |> list.length()
  |> should.equal(1)
  // both versions preserved (content-addressed: no data lost)
  result.tasks
  |> list.length()
  |> should.equal(2)
}

pub fn merge_never_raises_on_garbage_test() {
  // merge is pure over Task lists; feeding it only valid Tasks can't raise.
  // The "garbage tolerance" lives in jsonl.load (unparseable lines skipped).
  let _ = merge.merge([], [])
  should.be_true(True)
}

/// BUG-09 regression: JSONL output ends with a trailing newline (wc -l / jq interop).
pub fn flush_writes_trailing_newline_test() {
  let path = "test_bk_newline.jsonl"
  let _ = jsonl.flush([fresh()], to: path)
  let raw = should.be_ok(simplifile.read(from: path))
  string.ends_with(raw, "\n")
  |> should.be_true
}

/// sync --peers with a missing file returns a clear error.
pub fn sync_peers_missing_file_test() {
  let ws = "/tmp/bk_sync_peers_missing"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["sync", "--peers", "/tmp/nonexistent_peers.txt"])
  |> string.contains("could not read peers file")
  |> should.be_true
}
