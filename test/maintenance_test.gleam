//// Tests for the maintenance & export commands: backup, export, gc.

import bankai/cli
import bankai/serde
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
  let _ = simplifile.write("", to: ws <> "/messages.jsonl")
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

pub fn backup_writes_timestamped_copy_test() {
  let ws = "/tmp/bk_backup_writes"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "A"])
  let out = cli.run_in(ws, ["backup"])
  out |> string.contains("backed up") |> should.be_true
  out |> string.contains("tasks.jsonl") |> should.be_true
  out |> string.contains(".bak.") |> should.be_true
}

pub fn export_md_renders_checklist_test() {
  let ws = "/tmp/bk_export_md"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Open task"])
  let task = task_of(cli.run_in(ws, ["create", "Done task"]))
  let _ = cli.run_in(ws, ["update", task.id, "completed"])
  let out = cli.run_in(ws, ["export", "--format", "md"])
  out |> string.contains("- [ ] Open task") |> should.be_true
  out |> string.contains("- [x] Done task") |> should.be_true
}

pub fn export_json_returns_task_array_test() {
  let ws = "/tmp/bk_export_json"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "A"])
  let out = cli.run_in(ws, ["export", "--format", "json"])
  out |> string.contains("\"title\":\"A\"") |> should.be_true
  out |> string.contains("[") |> should.be_true
}

pub fn gc_retires_closed_tasks_test() {
  let ws = "/tmp/bk_gc_retires"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = task_of(cli.run_in(ws, ["create", "To close"]))
  let _ = cli.run_in(ws, ["update", task.id, "closed"])
  let out = cli.run_in(ws, ["gc"])
  out |> string.contains("retired") |> should.be_true
  // After gc, the closed task should no longer appear in current tasks.
  let list_out = cli.run_in(ws, ["list"])
  list_out |> string.contains("To close") |> should.be_false
}
