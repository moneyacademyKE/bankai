import bankai/daemon_store
import bankai/mcp
import bankai/mnesia_store
import bankai/socket
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_task_query_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

fn raw(value: Result(json.Json, String)) -> String {
  value |> should.be_ok |> json.to_string
}

pub fn one_spec_drives_list_count_and_blocked_test() {
  reset()
  let _ =
    should.be_ok(
      daemon_store.create(workspace, "Low bug", [
        "--kind",
        "bug",
        "--priority",
        "1",
        "--label",
        "api",
      ]),
    )
  let created =
    should.be_ok(
      daemon_store.create(workspace, "High bug", [
        "--kind",
        "bug",
        "--priority",
        "9",
        "--label",
        "api",
      ]),
    )
  let high = json.to_string(created)
  let high_id =
    high
    |> string.split("\"id\":\"")
    |> fn(parts) {
      case parts {
        [_, tail, ..] ->
          tail
          |> string.split("\"")
          |> fn(values) {
            case values {
              [id, ..] -> id
              _ -> ""
            }
          }
        _ -> ""
      }
    }
  let _ = should.be_ok(daemon_store.update(workspace, high_id, "blocked"))

  let args = [
    "--kind", "bug", "--label-all", "api", "--priority-min", "5", "--sort",
    "priority", "--desc", "--offset", "0", "--limit", "1",
  ]
  let listed = raw(daemon_store.list_tasks(workspace, args))
  listed |> string.contains("High bug") |> should.be_true
  listed |> string.contains("Low bug") |> should.be_false
  listed |> string.contains("\"total\":1") |> should.be_true

  raw(daemon_store.count_tasks(workspace, args))
  |> string.contains("\"count\":1")
  |> should.be_true

  raw(daemon_store.blocked_tasks(workspace, args))
  |> string.contains("High bug")
  |> should.be_true
}

pub fn compact_projection_and_ready_explanations_are_data_shaped_test() {
  reset()
  let blocker = should.be_ok(daemon_store.create(workspace, "Blocker", []))
  let dependent =
    should.be_ok(
      daemon_store.create(workspace, "Dependent", [
        "--label",
        "api",
      ]),
    )
  let blocker_id = json.to_string(blocker)
  let dependent_id = json.to_string(dependent)
  let extract = fn(value: String) {
    value
    |> string.split("\"id\":\"")
    |> fn(parts) {
      case parts {
        [_, tail, ..] ->
          tail
          |> string.split("\"")
          |> fn(values) {
            case values {
              [id, ..] -> id
              _ -> ""
            }
          }
        _ -> ""
      }
    }
  }
  let _ =
    should.be_ok(
      daemon_store.add_dependency(
        workspace,
        extract(dependent_id),
        extract(blocker_id),
        [],
      ),
    )

  let compact =
    raw(daemon_store.list_tasks(workspace, ["--compact", "--label", "api"]))
  compact |> string.contains("\"title\":\"Dependent\"") |> should.be_true
  compact |> string.contains("relationships") |> should.be_false

  let explained =
    raw(daemon_store.ready_tasks(workspace, ["--explain", "--label", "api"]))
  explained |> string.contains("\"ready\":false") |> should.be_true
  explained |> string.contains("\"active\":true") |> should.be_true
  explained |> string.contains("\"deferred\":false") |> should.be_true
  explained |> string.contains("\"gate_open\":true") |> should.be_true
  explained |> string.contains("\"claimable\":false") |> should.be_true
  explained |> string.contains("\"blockers\"") |> should.be_true
}

pub fn structured_queries_are_socket_and_mcp_visible_test() {
  reset()
  let _ =
    should.be_ok(
      daemon_store.create(workspace, "Feature", [
        "--kind",
        "feature",
      ]),
    )
  case
    socket.handle_request(
      workspace,
      socket.Request("list", ["--kind", "feature", "--compact"]),
    )
  {
    socket.OkResponse(value) ->
      value |> string.contains("Feature") |> should.be_true
    socket.ErrorResponse(_) -> False |> should.be_true
  }

  let tools =
    mcp.handle_message(
      workspace,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    )
  tools |> string.contains("structured query") |> should.be_true
  tools |> string.contains("\"name\":\"count\"") |> should.be_true
  tools |> string.contains("\"name\":\"blocked\"") |> should.be_true
}
