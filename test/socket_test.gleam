import bankai/cli
import bankai/socket
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const ws = "/tmp/bankai_socket_wire"

/// A JSON-RPC request line round-trips to a JSON-RPC response line with the
/// matching id, dispatching to the same ops as the CLI.
pub fn handle_line_roundtrip_test() {
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Wire test task"])
  let req = "{\"method\":\"ready\",\"params\":[],\"id\":7}"
  let resp = socket.handle_line(ws, req)
  resp
  |> string.contains("\"id\":7")
  |> should.be_true

  resp
  |> string.contains("\"result\"")
  |> should.be_true
}

/// create then ready over the wire handler surfaces the created task.
pub fn handle_line_create_then_ready_test() {
  let _ = cli.run_in(ws, ["init"])
  let created =
    socket.handle_line(
      ws,
      "{\"method\":\"create\",\"params\":[\"daemon task\"],\"id\":1}",
    )
  created
  |> string.contains("\"result\"")
  |> should.be_true

  let ready =
    socket.handle_line(ws, "{\"method\":\"ready\",\"params\":[],\"id\":2}")
  ready
  |> string.contains("daemon task")
  |> should.be_true
}

/// Daemon dispatch owns the MCP memory surface; these operations must not fall
/// through to the JSONL-backed CLI dispatcher.
pub fn daemon_memory_operations_test() {
  let _ = socket.handle_request(ws, socket.Request("init", []))

  case
    socket.handle_request(ws, socket.Request("remember", ["daemon insight"]))
  {
    socket.OkResponse(value) ->
      value |> string.contains("daemon insight") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }

  case socket.handle_request(ws, socket.Request("memories", [])) {
    socket.OkResponse(value) ->
      value |> string.contains("daemon insight") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }

  case socket.handle_request(ws, socket.Request("compact", [])) {
    socket.OkResponse(value) ->
      value |> string.contains("nothing to compact") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
}

pub fn handle_line_parse_error_test() {
  socket.handle_line(ws, "not json")
  |> string.contains("\"error\"")
  |> should.be_true
}
