//// bankai — content-addressed task memory for distributed AI agents.
////
//// This root module owns the process entry point (`main`). `cli` and `socket`
//// are kept separate so the protocol/CLI surface stays pure and testable;
//// `socket` imports `cli` (not the reverse), so neither may import this root.

import bankai/cli
import bankai/mcp
import bankai/socket
import gleam/io

pub const version = "0.1.0"

pub fn version_string() -> String {
  version
}

/// Entry point for `gleam run -m bankai -- <args>` / the `bankai` escript.
pub fn main() -> Nil {
  let args = argv()
  case args {
    // Long-running servers — block, no single-shot envelope.
    ["serve", ..] -> socket.serve(cli.default_workspace)
    ["mcp", ..] -> mcp.serve(cli.default_workspace)
    [] -> io.println(cli.usage())
    [method, ..params] -> {
      // Warm path first: if a daemon is listening on the socket, route the
      // request through it (no per-command BEAM cold start). Otherwise the
      // connect fails and we fall back to single-shot over the JSONL store.
      case socket.client_request(cli.default_workspace, method, params) {
        Ok(out) -> io.println(out)
        Error(_) -> io.println(cli.run_in(cli.default_workspace, args))
      }
    }
  }
}

@external(erlang, "bankai_argv_ffi", "get_args")
fn argv() -> List(String)
