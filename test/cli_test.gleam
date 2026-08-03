import bankai/cli
import bankai/serde
import bankai/socket
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
    socket.Result(value) ->
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
    socket.Result(_) -> should.be_true(False)
  }
}
