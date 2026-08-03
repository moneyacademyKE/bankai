//// Relations (--type) + priority (--priority) — high-utility / low-complexity
//// gap-closers: the RelationType model + Task.priority field already existed;
//// this wires them into the CLI.

import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) {
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

// --- non-Blocks relations (dep add --type) ---

pub fn dep_add_relates_to_is_not_a_blocker_test() {
  let ws = "/tmp/bankai_rel_rt"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Task A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws, ["create", "Task B"])))
  // dep add A B --type relates-to → A relates-to B (NOT blocked).
  let updated =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["dep", "add", a.id, b.id, "--type", "relates-to"]),
      ),
    )
  list.length(updated.relationships) |> should.equal(1)
  // A is NOT blocked → still ready.
  cli.run_in(ws, ["ready"]) |> string.contains("Task A") |> should.be_true
}

pub fn dep_add_type_defaults_to_blocks_test() {
  let ws = "/tmp/bankai_rel_def"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws, ["create", "A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws, ["create", "B"])))
  // no --type → Blocks → A blocked by B (B open) → A NOT ready, B IS ready.
  let _ = cli.run_in(ws, ["dep", "add", a.id, b.id])
  let ready = cli.run_in(ws, ["ready"])
  ready |> string.contains("\"title\":\"B\"") |> should.be_true
  ready |> string.contains("\"title\":\"A\"") |> should.be_false
}

pub fn dep_add_blocks_still_cycle_checks_test() {
  let ws = "/tmp/bankai_rel_cyc"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws, ["create", "A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws, ["create", "B"])))
  let _ = cli.run_in(ws, ["dep", "add", a.id, b.id])
  // B → A (blocks) closes a cycle → rejected.
  cli.run_in(ws, ["dep", "add", b.id, a.id])
  |> string.contains("cycle")
  |> should.be_true
}

pub fn dep_add_non_blocks_skips_cycle_check_test() {
  let ws = "/tmp/bankai_rel_nc"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws, ["create", "A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws, ["create", "B"])))
  let _ = cli.run_in(ws, ["dep", "add", a.id, b.id, "--type", "relates-to"])
  // B relates-to A — would-be a cycle for blocks, but relates-to isn't a
  // dependency → allowed (ok envelope, not a cycle error).
  cli.run_in(ws, ["dep", "add", b.id, a.id, "--type", "relates-to"])
  |> string.starts_with("{\"ok\"")
  |> should.be_true
}

// --- priority (create --priority) ---

pub fn create_with_priority_sets_field_test() {
  let ws = "/tmp/bankai_prio_set"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["create", "Urgent", "--priority", "5"])),
    )
  task.priority |> should.equal(5)
}

pub fn create_priority_defaults_to_one_test() {
  let ws = "/tmp/bankai_prio_def"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Normal"])))
  task.priority |> should.equal(1)
}
