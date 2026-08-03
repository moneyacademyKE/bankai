import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/string
import bankai/socket

//// Self-contained daemon probe: spawn the server, round-trip client requests
//// over the real UNIX socket, then exit (which tears down the spawned server).
//// Run: gleam run -m bankai/daemon_probe

pub fn main() -> Nil {
  let ws = "/tmp/bankai_daemon_probe"
  let _ = process.spawn(fn() { socket.serve(ws) })
  process.sleep(300)

  io.println("init   -> " <> show(socket.client_request(ws, "init", [])))
  io.println("create -> " <> show(socket.client_request(ws, "create", ["probe task"])))
  io.println("ready  -> " <> show(socket.client_request(ws, "ready", [])))
  io.println("prime  -> " <> show(socket.client_request(ws, "prime", [])))
  io.println("bogus  -> " <> show(socket.client_request(ws, "frobnicate", [])))
}

fn show(r: Result(String, String)) -> String {
  case r {
    Ok(s) ->
      "OK len=" <> int.to_string(string.length(s)) <> " :: "
      <> string.slice(s, 0, 70)
    Error(e) -> "ERR " <> e
  }
}
