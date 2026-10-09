import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
import gleam/option
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

/// bk-9f48: claiming a closed task fails loudly (embedded path previously
/// guarded nothing).
pub fn claim_closed_task_fails_test() {
  let ws = "/tmp/bankai_claim_closed"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Close me"])
  let assert Ok(task) = task_from_output(created)
  let _ = cli.run_in(ws, ["update", task.id, "closed"])
  let out = cli.run_in(ws, ["update", task.id, "--claim", "bob"])
  out |> string.contains("error") |> should.be_true
  out |> string.contains("not open") |> should.be_true
}

/// bk-9f48: claiming a task owned by someone else fails (silent steal).
pub fn claim_steal_fails_test() {
  let ws = "/tmp/bankai_claim_steal"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Mine"])
  let assert Ok(task) = task_from_output(created)
  let _ = cli.run_in(ws, ["update", task.id, "--claim", "alice"])
  let out = cli.run_in(ws, ["update", task.id, "--claim", "bob"])
  out |> string.contains("error") |> should.be_true
  out |> string.contains("already claimed by alice") |> should.be_true
  let shown = cli.run_in(ws, ["show", task.id])
  shown |> string.contains("\"alice\"") |> should.be_true
}

/// bk-9f48: --force is the explicit fence for reclaiming another's claim.
pub fn claim_force_overrides_test() {
  let ws = "/tmp/bankai_claim_force"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Takeable"])
  let assert Ok(task) = task_from_output(created)
  let _ = cli.run_in(ws, ["update", task.id, "--claim", "alice"])
  let out = cli.run_in(ws, ["update", task.id, "--claim", "bob", "--force"])
  let assert Ok(updated) = task_from_output(out)
  updated.assignee |> should.equal(option.Some("bob"))
}

/// bk-9f48: re-claiming your own task is an idempotent no-op, not an error.
pub fn claim_same_assignee_idempotent_test() {
  let ws = "/tmp/bankai_claim_same"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Still mine"])
  let assert Ok(task) = task_from_output(created)
  let once = cli.run_in(ws, ["update", task.id, "--claim", "alice"])
  let assert Ok(first) = task_from_output(once)
  let twice = cli.run_in(ws, ["update", task.id, "--claim", "alice"])
  let assert Ok(second) = task_from_output(twice)
  second.assignee |> should.equal(option.Some("alice"))
  second.content_hash |> should.equal(first.content_hash)
}
