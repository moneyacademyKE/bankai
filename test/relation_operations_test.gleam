import bankai/daemon_store
import bankai/mcp
import bankai/mnesia_store
import bankai/service_auth
import bankai/socket
import bankai/types
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_relation_operations_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

fn task_id(value: json.Json) -> String {
  let raw = json.to_string(value)
  raw
  |> string.split("\"id\":\"")
  |> list.drop(1)
  |> list.first()
  |> fn(part) {
    case part {
      Ok(value) -> value |> string.split("\"") |> first_or_empty
      Error(_) -> ""
    }
  }
}

fn first_or_empty(values: List(String)) -> String {
  case list.first(values) {
    Ok(value) -> value
    Error(_) -> ""
  }
}

fn create(title: String) -> String {
  daemon_store.create(workspace, title, [])
  |> should.be_ok
  |> task_id
}

pub fn live_daemon_allows_non_blocking_relation_that_closes_blocking_path_test() {
  reset()
  let a = create("A")
  let b = create("B")
  let _ = should.be_ok(daemon_store.add_dependency(workspace, b, a, []))

  daemon_store.add_dependency(workspace, a, b, ["--type", "relates_to"])
  |> should.be_ok

  let task = should.be_ok(mnesia_store.get_current(workspace, a))
  task.relationships
  |> list.any(fn(relation) {
    relation.target_id == b && relation.relation == types.RelatesTo
  })
  |> should.be_true
}

pub fn blocking_relation_that_closes_cycle_is_still_rejected_test() {
  reset()
  let a = create("A")
  let b = create("B")
  let _ = should.be_ok(daemon_store.add_dependency(workspace, b, a, []))

  daemon_store.add_dependency(workspace, a, b, [])
  |> should.be_error
}

pub fn relation_remove_is_typed_and_idempotent_test() {
  reset()
  let a = create("A")
  let b = create("B")
  let _ =
    should.be_ok(
      daemon_store.add_dependency(workspace, a, b, ["--type", "relates_to"]),
    )

  daemon_store.remove_dependency(workspace, a, b, ["--type", "relates_to"])
  |> should.be_ok
  daemon_store.remove_dependency(workspace, a, b, ["--type", "relates_to"])
  |> should.be_ok

  let task = should.be_ok(mnesia_store.get_current(workspace, a))
  task.relationships |> should.equal([])
}

pub fn relation_traversal_filters_direction_type_and_depth_test() {
  reset()
  let a = create("A")
  let b = create("B")
  let c = create("C")
  let _ = should.be_ok(daemon_store.add_dependency(workspace, a, b, []))
  let _ = should.be_ok(daemon_store.add_dependency(workspace, b, c, []))
  let _ =
    should.be_ok(
      daemon_store.add_dependency(workspace, c, a, ["--type", "relates_to"]),
    )

  let outgoing =
    should.be_ok(
      daemon_store.traverse_dependencies(workspace, a, [
        "--direction",
        "outgoing",
        "--type",
        "blocks",
        "--depth",
        "2",
      ]),
    )
  let raw = json.to_string(outgoing)
  raw |> string.contains(b) |> should.be_true
  raw |> string.contains(c) |> should.be_true
  raw |> string.contains("relates_to") |> should.be_false

  let incoming =
    should.be_ok(
      daemon_store.traverse_dependencies(workspace, a, [
        "--direction",
        "incoming",
        "--type",
        "relates_to",
        "--depth",
        "1",
      ]),
    )
  json.to_string(incoming) |> string.contains(c) |> should.be_true
}

pub fn graph_export_and_integrity_are_socket_routable_test() {
  reset()
  let a = create("A")
  let b = create("B")
  let _ = should.be_ok(daemon_store.add_dependency(workspace, a, b, []))

  case
    socket.handle_request(
      workspace,
      socket.Request("dep_graph", ["--type", "blocks"]),
    )
  {
    socket.OkResponse(value) -> {
      value |> string.contains("edges") |> should.be_true
      value |> string.contains(a) |> should.be_true
      value |> string.contains(b) |> should.be_true
    }

    socket.ErrorResponse(_) -> False |> should.be_true
  }

  case socket.handle_request(workspace, socket.Request("dep_check", [])) {
    socket.OkResponse(value) ->
      value |> string.contains("\"healthy\":true") |> should.be_true
    socket.ErrorResponse(_) -> False |> should.be_true
  }
}

pub fn relation_operations_are_advertised_through_mcp_test() {
  reset()
  let _ = should.be_ok(service_auth.local_admin_token(workspace))
  let tools =
    mcp.handle_message(
      workspace,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/list\"}",
    )
  tools |> string.contains("dep_remove") |> should.be_true
  tools |> string.contains("dep_traverse") |> should.be_true
  tools |> string.contains("dep_graph") |> should.be_true
  tools |> string.contains("dep_check") |> should.be_true
}
