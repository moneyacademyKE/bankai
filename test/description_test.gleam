import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
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

/// G9: unwrap a {"ok": <task>} envelope into the Task.
fn ok_task_decoder() -> decode.Decoder(types.Task) {
  use task <- decode.field("ok", serde.task_decoder())
  decode.success(task)
}

fn task_from_output(output: String) -> Result(types.Task, json.DecodeError) {
  json.parse(from: output, using: ok_task_decoder())
}

/// create --description D must store D on the task (was silently hardcoded "").
pub fn create_description_is_stored_test() {
  let ws = "/tmp/bankai_desc_create"
  wipe(ws)
  let output =
    cli.run_in(ws, [
      "create",
      "Socket fix",
      "--description",
      "fix the line split",
    ])
  let assert Ok(task) = task_from_output(output)
  task.description |> should.equal("fix the line split")
}

/// Back-compat: create without --description keeps the empty description.
pub fn create_without_description_defaults_empty_test() {
  let ws = "/tmp/bankai_desc_default"
  wipe(ws)
  let output = cli.run_in(ws, ["create", "No desc"])
  let assert Ok(task) = task_from_output(output)
  task.description |> should.equal("")
}

/// Description must not swallow the title or collide with other flags.
pub fn create_description_with_labels_test() {
  let ws = "/tmp/bankai_desc_combo"
  wipe(ws)
  let output =
    cli.run_in(ws, [
      "create", "Combo", "--label", "bug", "--description", "multi flag",
      "--priority", "2",
    ])
  let assert Ok(task) = task_from_output(output)
  task.title |> should.equal("Combo")
  task.description |> should.equal("multi flag")
  task.labels |> should.equal(["bug"])
  task.priority |> should.equal(2)
}
