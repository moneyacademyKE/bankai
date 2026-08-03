import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
import gleam/string
import gleamunison/identity
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

/// G3: `create --label` persists labels onto the task.
pub fn create_with_labels_persists_them_test() {
  let ws = "/tmp/bankai_labels_create"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let out =
    cli.run_in(ws, ["create", "Labeled", "--label", "bug", "--label", "ui"])

  out |> string.contains("\"bug\"") |> should.be_true
  out |> string.contains("\"ui\"") |> should.be_true
}

/// G3: `list --label L` filters to tasks carrying L.
pub fn list_filters_by_label_test() {
  let ws = "/tmp/bankai_labels_filter"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Bug one", "--label", "bug"])
  let _ = cli.run_in(ws, ["create", "Feature two", "--label", "feat"])

  let bug_list = cli.run_in(ws, ["list", "--label", "bug"])
  bug_list |> string.contains("Bug one") |> should.be_true
  bug_list |> string.contains("Feature two") |> should.be_false
}

/// G3: `update <id> --label L` adds a label; adding twice is a no-op (hash
/// unchanged — the content-addressing invariant holds).
pub fn update_adds_label_and_is_idempotent_test() {
  let ws = "/tmp/bankai_labels_update"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let created = cli.run_in(ws, ["create", "Plain"])
  let task = should.be_ok(task_from_output(created))

  let once =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["update", task.id, "--label", "urgent"])),
    )
  once.labels |> should.equal(["urgent"])

  // idempotent: same label again -> hash unchanged.
  let twice =
    should.be_ok(
      task_from_output(cli.run_in(ws, ["update", task.id, "--label", "urgent"])),
    )
  identity.hash_equal(twice.content_hash, once.content_hash)
  |> should.be_true
}
