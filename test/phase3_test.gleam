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

/// G10: create --parent produces a hierarchical id "<parent>.<n>", incrementing.
pub fn create_with_parent_gets_hierarchical_id_test() {
  let ws = "/tmp/bankai_phase3_hier"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let parent =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Parent"])))
  let child1 =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["create", "First child", "--parent", parent.id]),
      ),
    )
  child1.id |> should.equal(parent.id <> ".1")
  let child2 =
    should.be_ok(
      task_from_output(
        cli.run_in(ws, ["create", "Second child", "--parent", parent.id]),
      ),
    )
  child2.id |> should.equal(parent.id <> ".2")
}

/// G10: a missing parent is rejected.
pub fn create_with_missing_parent_errors_test() {
  let ws = "/tmp/bankai_phase3_orphan"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["create", "Orphan", "--parent", "bk-nope"])
  |> string.contains("no such parent")
  |> should.be_true
}

/// G7: setup emits the bankai workflow into the agent-instruction file.
pub fn agent_instructions_describe_workflow_test() {
  let body = cli.agent_instructions()
  body |> string.contains("bankai ready") |> should.be_true
  body |> string.contains("hierarchical") |> should.be_true
  body |> string.contains("remember") |> should.be_true
}
