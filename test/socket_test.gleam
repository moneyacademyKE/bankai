import bankai/cli
import bankai/socket
import gleam/erlang/process
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

/// Round 4: a bound socket reports owned; a missing path does not.
pub fn socket_owned_reports_live_daemon_test() {
  let ws2 = "/tmp/bankai_socket_owned"
  let _ = cli.run_in(ws2, ["init"])
  let path = socket.socket_path(ws2)
  socket.socket_owned(path) |> should.be_false
  let _ = process.spawn_unlinked(fn() { socket.serve(ws2) })
  process.sleep(2000)
  socket.socket_owned(path) |> should.be_true
  // A path that was never bound is not owned.
  socket.socket_owned("/tmp/bankai_never_existed.sock") |> should.be_false
}

/// Round 5: daemon-path history on a ghost id errors loudly,
/// matching the embedded path's contract.
pub fn history_ghost_id_errors_test() {
  let ws = "/tmp/bankai_socket_history_ghost"
  let _ = cli.run_in(ws, ["init"])
  case socket.handle_request(ws, socket.Request("history", ["bk-ghost"])) {
    socket.ErrorResponse(message) ->
      message |> string.contains("no such task") |> should.be_true
    socket.OkResponse(_) -> should.be_true(False)
  }
}
