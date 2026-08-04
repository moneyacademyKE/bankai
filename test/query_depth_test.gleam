//// Tests for the query-depth commands: cycles, duplicates, stale.
////
//// These reuse graph primitives / the relation model — no SQL engine.
//// `cycles` is a diagnostic over merged/foreign data: the local `dep add`
//// guards against adding cycles, so a cycle can only reach the store through a
//// mimic that path.

/// union-merge with a peer that did not guard. The test seeds one directly to
import bankai/builder
import bankai/cli
import bankai/serde
import bankai/sync/jsonl
import bankai/types
import gleam/option
import gleam/string
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
  Nil
}

/// Seed tasks.jsonl directly with controlled timestamps/relationships so the
/// drift filter and cycle detector can be exercised deterministically (the
/// public CLI only ever stamps `now()` and guards against adding cycles).
fn seed(ws: String, tasks: List(types.Task)) -> Nil {
  let _ = jsonl.flush(tasks, to: ws <> "/tasks.jsonl")
  Nil
}

/// Peel `{ok: ...}` off a single-task command output, returning a JSON
/// string `serde.task_from_json_string` can decode. Gleam's `json.to_string`
/// produces compact JSON (no spaces after colons): {"ok":{...}}.
fn task_json(output: String) -> String {
  let stripped = string.replace(output, "{\"ok\":", "")
  let n = string.length(stripped)
  string.slice(stripped, 0, n - 1)
}

fn task_of(output: String) -> types.Task {
  should.be_ok(serde.task_from_json_string(task_json(output)))
}

@external(erlang, "erlang", "system_time")
fn now() -> Int

// --- cycles ---

pub fn cycles_empty_on_acyclic_graph_test() {
  let ws = "/tmp/bk_qd_cycles_acyclic"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = task_of(cli.run_in(ws, ["create", "A"])).id
  let b = task_of(cli.run_in(ws, ["create", "B"])).id
  let _ = cli.run_in(ws, ["dep", "add", a, b])
  // A depends on B — acyclic
  let out = cli.run_in(ws, ["cycles"])
  out |> string.contains("\"from\"") |> should.be_false
}

/// A cycle that arrived via a merged peer (whence else — `dep add` guards it):
/// seed A->B and B->A directly, then `cycles` must report the back edges.
pub fn cycles_reports_merged_cycle_test() {
  let ws = "/tmp/bk_qd_cycles_back"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task_a = task_of(cli.run_in(ws, ["create", "A"]))
  let task_b = task_of(cli.run_in(ws, ["create", "B"]))
  let ab = add_block(task_a, task_b.id)
  let ba = add_block(task_b, task_a.id)
  seed(ws, [ab, ba])
  let out = cli.run_in(ws, ["cycles"])
  out |> string.contains("\"from\"") |> should.be_true
  out |> string.contains(task_a.id) |> should.be_true
  out |> string.contains(task_b.id) |> should.be_true
}

// --- duplicates ---

pub fn duplicates_lists_related_pairs_test() {
  let ws = "/tmp/bk_qd_dup_pairs"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = task_of(cli.run_in(ws, ["create", "A"])).id
  let b = task_of(cli.run_in(ws, ["create", "B"])).id
  let _ = cli.run_in(ws, ["dep", "add", a, b, "--type", "duplicates"])
  let out = cli.run_in(ws, ["duplicates"])
  out |> string.contains("\"a\"") |> should.be_true
  out |> string.contains(a) |> should.be_true
  out |> string.contains(b) |> should.be_true
}

pub fn duplicates_ignores_blocks_relations_test() {
  let ws = "/tmp/bk_qd_dup_no_blocks"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = task_of(cli.run_in(ws, ["create", "A"])).id
  let b = task_of(cli.run_in(ws, ["create", "B"])).id
  let _ = cli.run_in(ws, ["dep", "add", a, b])
  // default Blocks
  cli.run_in(ws, ["duplicates"])
  |> string.contains("\"a\"")
  |> should.be_false
}

// --- stale ---

pub fn stale_flags_old_active_tasks_test() {
  let ws = "/tmp/bk_qd_stale_old"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let now_ts = now()
  let old = now_ts - 10 * 86_400
  // Seed one fresh active task and one stale active task directly.
  let fresh =
    builder.build(
      "bk-fresh",
      "Fresh one",
      "",
      types.Open,
      option.None,
      1,
      now_ts,
      now_ts,
      [],
    )
  let stale_task =
    builder.build(
      "bk-stale",
      "Stale one",
      "",
      types.Open,
      option.None,
      1,
      old,
      old,
      [],
    )
  seed(ws, [fresh, stale_task])
  let out = cli.run_in(ws, ["stale", "--days", "7"])
  out |> string.contains("Stale one") |> should.be_true
  out |> string.contains("Fresh one") |> should.be_false
}

pub fn stale_excludes_completed_tasks_test() {
  let ws = "/tmp/bk_qd_stale_done"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let old = now() - 30 * 86_400
  let done_old =
    builder.build(
      "bk-done",
      "Done long ago",
      "",
      types.Completed,
      option.None,
      1,
      old,
      old,
      [],
    )
  seed(ws, [done_old])
  cli.run_in(ws, ["stale", "--days", "7"])
  |> string.contains("Done long ago")
  |> should.be_false
}

pub fn stale_uses_default_7_days_test() {
  let ws = "/tmp/bk_qd_stale_default"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let old = now() - 8 * 86_400
  // 8 days -> stale under the default 7
  let srv =
    builder.build(
      "bk-old8",
      "Old eight days",
      "",
      types.Open,
      option.None,
      1,
      old,
      old,
      [],
    )
  seed(ws, [srv])
  cli.run_in(ws, ["stale"])
  |> string.contains("Old eight days")
  |> should.be_true
}

// --- seed helpers ---

/// Add a Blocks relationship to a task and rehash (the store-level mutation the
/// `dep add` CLI applies — used here to construct a cycle directly, bypassing the
/// guard, which mirrors a merged peer that did not guard).
fn add_block(t: types.Task, target: String) -> types.Task {
  builder.update(t, fn(task) {
    types.Task(..task, relationships: [
      types.Relationship(target_id: target, relation: types.Blocks),
      ..task.relationships
    ])
  })
}
