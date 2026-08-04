//// Tests for the messaging commands: msg add, msg list.
////
//// Messages are content-addressed (like tasks and memories) and
//// threaded via parent_msg_id. This test exercises the full round-
//// trip: add a message, list it back, verify threading.

import bankai/cli
import bankai/message
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

pub fn msg_add_persists_and_returns_test() {
  let ws = "/tmp/bk_msg_add"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = task_of(cli.run_in(ws, ["create", "Work item"]))
  let text = "started on this"
  let out = cli.run_in(ws, ["msg", "add", task.id, text])
  out |> string.contains("\"text\":\"" <> text <> "\"") |> should.be_true
  out |> string.contains("\"task_id\":\"" <> task.id <> "\"") |> should.be_true
  out |> string.contains("\"author\":\"agent\"") |> should.be_true
}

pub fn msg_add_rejects_missing_task_test() {
  let ws = "/tmp/bk_msg_missing_task"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["msg", "add", "bk-nonexistent", "hello"])
  |> string.contains("no such task")
  |> should.be_true
}

pub fn msg_list_returns_task_messages_test() {
  let ws = "/tmp/bk_msg_list"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = task_of(cli.run_in(ws, ["create", "Work item"]))
  let _ = cli.run_in(ws, ["msg", "add", task.id, "first note"])
  let _ = cli.run_in(ws, ["msg", "add", task.id, "second note"])
  let out = cli.run_in(ws, ["msg", "list", task.id])
  out |> string.contains("first note") |> should.be_true
  out |> string.contains("second note") |> should.be_true
  // Messages for other tasks should not appear.
  let other = task_of(cli.run_in(ws, ["create", "Other"]))
  let _ = cli.run_in(ws, ["msg", "add", other.id, "other note"])
  out |> string.contains("other note") |> should.be_false
}

pub fn msg_add_threading_via_reply_test() {
  let ws = "/tmp/bk_msg_thread"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let task = task_of(cli.run_in(ws, ["create", "Work item"]))
  // Post a top-level message, capture its id from the output.
  let add_out = cli.run_in(ws, ["msg", "add", task.id, "parent message"])
  let parent_msg =
    should.be_ok(message.message_from_json_string(task_json(add_out)))
  // Reply to it.
  let reply_out =
    cli.run_in(ws, [
      "msg",
      "add",
      task.id,
      "reply text",
      "--reply",
      parent_msg.id,
    ])
  let reply_msg =
    should.be_ok(message.message_from_json_string(task_json(reply_out)))
  // The reply should reference the parent.
  reply_msg.parent_msg_id |> should.equal(parent_msg.id)
  // List should show both, newest first.
  let list_out = cli.run_in(ws, ["msg", "list", task.id])
  list_out |> string.contains("reply text") |> should.be_true
  list_out |> string.contains("parent message") |> should.be_true
}
