import bankai/cli
import bankai/serde
import bankai/socket
import bankai/types
import gleam/string
import gleamunison/identity
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const ws_e2e = "/tmp/bankai_cli_e2e"

const ws_inspect = "/tmp/bankai_cli_inspect"

const ws_socket = "/tmp/bankai_cli_socket"

const ws_status = "/tmp/bankai_cli_status"

const ws_dataloss = "/tmp/bankai_cli_dataloss"

/// Full lifecycle: init -> create -> ready -> update -> inspect.
pub fn cli_e2e_smoke_test() {
  let _ = cli.run_in(ws_e2e, ["init"])
  let created = cli.run_in(ws_e2e, ["create", "Ship the bankai MVP"])
  let task = should.be_ok(serde.task_from_json_string(created))

  task.title
  |> should.equal("Ship the bankai MVP")

  // A freshly-created Open task with no blockers is ready.
  cli.run_in(ws_e2e, ["ready"])
  |> string.contains("Ship the bankai MVP")
  |> should.be_true

  // Mark it completed; it should no longer be ready.
  cli.run_in(ws_e2e, ["update", task.id, "completed"])
  |> string.contains("completed")
  |> should.be_true

  cli.run_in(ws_e2e, ["ready"])
  |> string.contains("Ship the bankai MVP")
  |> should.be_false
}

/// The content hash from `create` is inspectable end to end.
pub fn cli_inspect_roundtrip_test() {
  let _ = cli.run_in(ws_inspect, ["init"])
  let created = cli.run_in(ws_inspect, ["create", "Inspectable task"])
  let task = should.be_ok(serde.task_from_json_string(created))
  let hash = identity.hash_to_debug_string(task.content_hash)

  cli.run_in(ws_inspect, ["inspect", hash])
  |> string.contains("Inspectable task")
  |> should.be_true
}

pub fn prime_emits_agent_prompt_test() {
  cli.run_in(ws_e2e, ["prime"])
  |> string.contains("content-addressed")
  |> should.be_true
}

/// JSON-RPC protocol round-trips through the socket/daemon handler.
pub fn socket_jsonrpc_roundtrip_test() {
  let _ = socket.handle_request(ws_socket, socket.Request("init", []))
  let _ =
    socket.handle_request(
      ws_socket,
      socket.Request("create", ["socket-driven"]),
    )
  let resp = socket.handle_request(ws_socket, socket.Request("ready", []))

  case resp {
    socket.OkResponse(value) ->
      value
      |> string.contains("socket-driven")
      |> should.be_true
    socket.ErrorResponse(message) ->
      message
      |> should.equal("should not error")
  }
}

pub fn socket_unknown_method_errors_test() {
  case socket.handle_request(ws_socket, socket.Request("frobnicate", [])) {
    socket.ErrorResponse(_) -> should.be_true(True)
    socket.OkResponse(_) -> should.be_true(False)
  }
}

/// BUG-02 regression: `update` must accept ALL five status variants. The old
/// parse_status only knew open|in_progress|completed and rejected "blocked"
/// and "closed" as invalid — two valid transitions were unreachable from the
/// only user-facing surface. Now cli reuses serde.status_from_string (single
/// source of truth), so the parser can never drift from the round-trip again.
pub fn cli_update_accepts_blocked_and_closed_test() {
  let _ = cli.run_in(ws_status, ["init"])
  let created = cli.run_in(ws_status, ["create", "All-status task"])
  let task = should.be_ok(serde.task_from_json_string(created))

  // "blocked" must be accepted and round-trip through serde.
  cli.run_in(ws_status, ["update", task.id, "blocked"])
  |> serde.task_from_json_string
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Blocked)

  // "closed" likewise.
  cli.run_in(ws_status, ["update", task.id, "closed"])
  |> serde.task_from_json_string
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Closed)

  // An unknown status is still rejected.
  cli.run_in(ws_status, ["update", task.id, "frobnicated"])
  |> string.contains("invalid status")
  |> should.be_true
}

/// BUG-01 regression: updating one task must preserve every other task. The
/// old update_cmd reloaded the store between lookup and put — a TOCTOU window
/// that discarded sibling tasks on flush under a concurrent write, plus a
/// redundant disk read every update. The fix loads once and threads the same
/// store. This guard locks the invariant: after updating A, sibling B is still
/// present and still ready (Open), and A has the new status. It catches any
/// flush-only-the-updated-task regression.
pub fn cli_update_preserves_sibling_tasks_test() {
  let _ = cli.run_in(ws_dataloss, ["init"])
  let created_a = cli.run_in(ws_dataloss, ["create", "Keep task A"])
  let a = should.be_ok(serde.task_from_json_string(created_a))
  let _ = cli.run_in(ws_dataloss, ["create", "Keep task B"])

  // Update A to completed; it must round-trip with the new status.
  cli.run_in(ws_dataloss, ["update", a.id, "completed"])
  |> serde.task_from_json_string
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Completed)

  // Sibling B must survive the update unchanged.
  cli.run_in(ws_dataloss, ["list"])
  |> string.contains("Keep task B")
  |> should.be_true

  // B is still Open with no blockers, so it stays ready.
  cli.run_in(ws_dataloss, ["ready"])
  |> string.contains("Keep task B")
  |> should.be_true

  // A is now completed, so it must have left the ready set.
  cli.run_in(ws_dataloss, ["ready"])
  |> string.contains("Keep task A")
  |> should.be_false
}
