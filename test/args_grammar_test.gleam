import bankai/cli
import bankai/cli/parser
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

/// bk-57c1 A: `create --title "T"` must title the task "T", never the
/// literal string "--title" (embedded path previously took argv[1] raw).
pub fn create_title_flag_is_not_literal_test() {
  let ws = "/tmp/bankai_args_create_title"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let out =
    cli.run_in(ws, [
      "create",
      "--title",
      "Real Title",
      "--description",
      "desc text",
    ])
  out |> string.contains("\"--title\"") |> should.be_false
  out |> string.contains("Real Title") |> should.be_true
  out |> string.contains("desc text") |> should.be_true
}

/// bk-57c1 B: unknown create flags fail loudly instead of being ignored.
pub fn create_rejects_unknown_flag_test() {
  let ws = "/tmp/bankai_args_create_unknown"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let out = cli.run_in(ws, ["create", "T", "--bogus", "x"])
  out |> string.contains("error") |> should.be_true
  out |> string.contains("unknown") |> should.be_true
}

/// bk-57c1 C: `update <id> <status> --claim a` applies BOTH status and
/// assignee (previously the status arm swallowed the claim).
pub fn update_status_and_claim_compose_test() {
  let ws = "/tmp/bankai_args_update_compose"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Compose me"])
  let assert Ok(task) = task_from_output(created)
  let _ =
    cli.run_in(ws, ["update", task.id, "in_progress", "--claim", "agent-x"])
  let shown = cli.run_in(ws, ["show", task.id])
  shown |> string.contains("\"in_progress\"") |> should.be_true
  shown |> string.contains("agent-x") |> should.be_true
}

/// bk-57c1 D: unknown update flags fail loudly.
pub fn update_rejects_unknown_flag_test() {
  let ws = "/tmp/bankai_args_update_unknown"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "T"])
  let assert Ok(task) = task_from_output(created)
  let out = cli.run_in(ws, ["update", task.id, "--bogus"])
  out |> string.contains("error") |> should.be_true
  out |> string.contains("unknown") |> should.be_true
}

/// bk-57c1 E: labels and claim compose in one update.
pub fn update_labels_and_claim_compose_test() {
  let ws = "/tmp/bankai_args_update_labels_claim"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "T"])
  let assert Ok(task) = task_from_output(created)
  let _ =
    cli.run_in(ws, [
      "update",
      task.id,
      "--label",
      "a",
      "--label",
      "b",
      "--claim",
      "c",
    ])
  let shown = cli.run_in(ws, ["show", task.id])
  shown |> string.contains("\"a\"") |> should.be_true
  shown |> string.contains("\"b\"") |> should.be_true
  shown |> string.contains("\"c\"") |> should.be_true
}

pub fn validate_priority_rejects_out_of_range_test() {
  parser.validate_priority(99) |> should.be_error
  parser.validate_priority(-1) |> should.be_error
}

pub fn validate_priority_accepts_bounds_test() {
  parser.validate_priority(0) |> should.be_ok
  parser.validate_priority(5) |> should.be_ok
}

pub fn validate_title_rejects_empty_test() {
  parser.validate_title("") |> should.be_error
  parser.validate_title("   ") |> should.be_error
}

pub fn validate_title_trims_and_keeps_test() {
  parser.validate_title("  real title  ") |> should.equal(Ok("real title"))
}
