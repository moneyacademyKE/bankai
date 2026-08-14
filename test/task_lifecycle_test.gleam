import bankai/daemon_store
import bankai/mnesia_store
import bankai/service_auth
import bankai/socket
import bankai/types
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_lifecycle_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  service_auth.reset_for_test(workspace)
}

fn id(value: json.Json) -> String {
  json.to_string(value)
  |> string.split("\"id\":\"")
  |> list.drop(1)
  |> list.first
  |> fn(part) {
    case part {
      Ok(tail) -> tail |> string.split("\"") |> list.first |> result_or_empty
      Error(_) -> ""
    }
  }
}

fn result_or_empty(value: Result(String, Nil)) -> String {
  case value {
    Ok(found) -> found
    Error(_) -> ""
  }
}

fn create(title: String, args: List(String)) -> String {
  daemon_store.create(workspace, title, args) |> should.be_ok |> id
}

pub fn release_reopen_undefer_and_label_remove_are_idempotent_test() {
  reset()
  let claimed = create("Claimed", ["--label", "api"])
  let _ = should.be_ok(daemon_store.claim(workspace, claimed, ["alice"]))
  let released = should.be_ok(daemon_store.release(workspace, claimed))
  let released_hash =
    should.be_ok(mnesia_store.get_current(workspace, claimed)).content_hash
  daemon_store.release(workspace, claimed) |> should.be_ok
  should.be_ok(mnesia_store.get_current(workspace, claimed)).content_hash
  |> should.equal(released_hash)
  let released_task = should.be_ok(mnesia_store.get_current(workspace, claimed))
  released_task.status |> should.equal(types.Open)
  released_task.assignee |> should.equal(option.None)

  daemon_store.remove_label(workspace, claimed, "api") |> should.be_ok
  daemon_store.remove_label(workspace, claimed, "api") |> should.be_ok
  should.be_ok(mnesia_store.get_current(workspace, claimed)).labels
  |> should.equal([])

  let _ =
    should.be_ok(daemon_store.defer_until(
      workspace,
      claimed,
      "999999999999999999",
    ))
  daemon_store.undefer(workspace, claimed) |> should.be_ok
  daemon_store.undefer(workspace, claimed) |> should.be_ok
  should.be_ok(mnesia_store.get_current(workspace, claimed)).defer_until
  |> should.equal(option.None)

  let _ = should.be_ok(daemon_store.close(workspace, claimed, "not now"))
  daemon_store.reopen(workspace, claimed) |> should.be_ok
  let reopened = should.be_ok(mnesia_store.get_current(workspace, claimed))
  reopened.status |> should.equal(types.Open)
  reopened.closure_reason |> should.equal(option.None)
  json.to_string(released) |> string.contains(claimed) |> should.be_true
}

pub fn batch_is_atomic_and_idempotent_test() {
  reset()
  let a = create("A", [])
  let b = create("B", [])
  let _ = should.be_ok(daemon_store.claim(workspace, a, ["alice"]))
  let _ = should.be_ok(daemon_store.close(workspace, b, "not actionable"))
  let before_b = should.be_ok(mnesia_store.get_current(workspace, b))

  daemon_store.batch_mutate(workspace, "bad-batch", [
    "release:" <> a,
    "release:" <> b,
  ])
  |> should.be_error
  should.be_ok(mnesia_store.get_current(workspace, a)).status
  |> should.equal(types.InProgress)
  should.be_ok(mnesia_store.get_current(workspace, b)).content_hash
  |> should.equal(before_b.content_hash)

  let _ = should.be_ok(daemon_store.reopen(workspace, b))
  let first =
    should.be_ok(
      daemon_store.batch_mutate(workspace, "good-batch", [
        "release:" <> a,
        "priority:" <> b <> ":7",
      ]),
    )
  let replay =
    should.be_ok(
      daemon_store.batch_mutate(workspace, "good-batch", [
        "release:" <> a,
        "priority:" <> b <> ":7",
      ]),
    )
  json.to_string(first)
  |> string.contains("\"replayed\":false")
  |> should.be_true
  json.to_string(replay)
  |> string.contains("\"replayed\":true")
  |> should.be_true
  should.be_ok(mnesia_store.get_current(workspace, a)).status
  |> should.equal(types.Open)
  should.be_ok(mnesia_store.get_current(workspace, b)).priority
  |> should.equal(7)

  daemon_store.batch_mutate(workspace, "good-batch", ["priority:" <> b <> ":8"])
  |> should.be_error
}

pub fn lifecycle_and_batch_authorization_are_enforced_test() {
  reset()
  let task = create("Auth", [])
  let read = should.be_ok(service_auth.mint(workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(workspace, "write", 3600))

  let denied =
    "{\"method\":\"update\",\"params\":[\""
    <> task
    <> "\",\"--reopen\"],\"token\":\""
    <> read
    <> "\",\"id\":1}"
  socket.handle_authenticated_line(workspace, denied)
  |> string.contains("capability denied")
  |> should.be_true

  let allowed =
    "{\"method\":\"batch\",\"params\":[\"--idempotency-key\",\"auth\",\"priority:"
    <> task
    <> ":3\"],\"token\":\""
    <> write
    <> "\",\"id\":2}"
  socket.handle_authenticated_line(workspace, allowed)
  |> string.contains("applied 1 mutation")
  |> should.be_true
}
