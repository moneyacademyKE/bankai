//// Tests for the high-utility/low-complexity query + update commands:
//// count, blocked, update --priority.

import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
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

fn ok_task_decoder() -> decode.Decoder(types.Task) {
  use task <- decode.field("ok", serde.task_decoder())
  decode.success(task)
}

fn task_from_output(output: String) -> Result(types.Task, json.DecodeError) {
  json.parse(from: output, using: ok_task_decoder())
}

pub fn count_returns_total_current_tasks_test() {
  let ws = "/tmp/bankai_count_total"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "A"])
  let _ = cli.run_in(ws, ["create", "B"])
  let _ = cli.run_in(ws, ["create", "C"])
  cli.run_in(ws, ["count"])
  |> string.contains("\"count\":3")
  |> should.be_true
}

pub fn count_filters_by_label_test() {
  let ws = "/tmp/bankai_count_label"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "A", "--label", "bug"])
  let _ = cli.run_in(ws, ["create", "B", "--label", "feat"])
  let _ = cli.run_in(ws, ["create", "C", "--label", "bug"])
  cli.run_in(ws, ["count", "--label", "bug"])
  |> string.contains("\"count\":2")
  |> should.be_true
}

pub fn blocked_lists_only_blocked_tasks_test() {
  let ws = "/tmp/bankai_blocked_q"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let blocked_task =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Blocked one"])))
  let _ = cli.run_in(ws, ["create", "Open one"])
  let _ = cli.run_in(ws, ["update", blocked_task.id, "blocked"])
  let out = cli.run_in(ws, ["blocked"])
  out |> string.contains("Blocked one") |> should.be_true
  out |> string.contains("Open one") |> should.be_false
}

pub fn update_priority_changes_field_test() {
  let ws = "/tmp/bankai_upd_prio"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Prio"])))
  let updated =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["update", task.id, "--priority", "9"])),
    )
  updated.priority |> should.equal(9)
}

pub fn update_priority_rejects_non_integer_test() {
  let ws = "/tmp/bankai_upd_prio_bad"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = should.be_ok(task_from_output(cli.run_in(ws, ["create", "X"])))
  cli.run_in(ws, ["update", task.id, "--priority", "high"])
  |> string.contains("invalid priority")
  |> should.be_true
}
