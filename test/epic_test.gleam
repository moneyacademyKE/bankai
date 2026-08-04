//// Tests for the epic roll-up command: bankai epic <id>.
//// Hierarchical IDs (bk-XXXX.N) already encode parent→child via
//// the prefix scan in next_child_id; this command exposes the roll-up view.

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

fn seed(ws: String, tasks: List(types.Task)) -> Nil {
  let _ = jsonl.flush(tasks, to: ws <> "/tasks.jsonl")
  Nil
}

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

pub fn epic_rolls_up_children_test() {
  let ws = "/tmp/bk_epic_rollup"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let parent_id = "bk-epic-parent"
  let now_ts = now()

  let parent =
    builder.build(
      parent_id,
      "Epic: frontend",
      "",
      types.Open,
      option.None,
      1,
      now_ts,
      now_ts,
      [],
    )

  let child_open =
    builder.build(
      parent_id <> ".1",
      "Child open",
      "",
      types.Open,
      option.None,
      1,
      now_ts,
      now_ts,
      [],
    )

  let child_done =
    builder.build(
      parent_id <> ".2",
      "Child completed",
      "",
      types.Completed,
      option.None,
      1,
      now_ts,
      now_ts,
      [],
    )

  seed(ws, [parent, child_open, child_done])

  let out = cli.run_in(ws, ["epic", parent_id])
  out |> string.contains("\"children\":2") |> should.be_true
  out |> string.contains("\"open\":1") |> should.be_true
  out |> string.contains("\"completed\":1") |> should.be_true
  out |> string.contains("\"in_progress\":0") |> should.be_true
  out |> string.contains("\"blocked\":0") |> should.be_true
  out |> string.contains("\"closed\":0") |> should.be_true
  // 1 of 2 done = 50%
  out |> string.contains("\"completion_pct\":50.0") |> should.be_true
}

pub fn epic_no_children_returns_zero_test() {
  let ws = "/tmp/bk_epic_no_children"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let now_ts = now()
  let parent =
    builder.build(
      "bk-lone",
      "Lone task",
      "",
      types.Open,
      option.None,
      1,
      now_ts,
      now_ts,
      [],
    )
  seed(ws, [parent])

  let out = cli.run_in(ws, ["epic", "bk-lone"])
  out |> string.contains("\"children\":0") |> should.be_true
  out |> string.contains("\"completion_pct\":0.0") |> should.be_true
}

pub fn epic_rejects_missing_task_test() {
  let ws = "/tmp/bk_epic_missing"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["epic", "bk-nonexistent"])
  |> string.contains("no such task")
  |> should.be_true
}
