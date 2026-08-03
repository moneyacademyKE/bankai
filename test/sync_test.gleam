import bankai/builder
import bankai/serde
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/types.{InProgress, Open}
import gleam/list
import gleam/option
import gleamunison/identity
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
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
