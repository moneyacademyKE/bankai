import gleeunit
import gleeunit/should
import gleam/string
import bankai/cli
import bankai/socket

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

/// Malformed input becomes an error envelope, not a crash.
pub fn handle_line_parse_error_test() {
  socket.handle_line(ws, "not json")
  |> string.contains("\"error\"")
  |> should.be_true
}
