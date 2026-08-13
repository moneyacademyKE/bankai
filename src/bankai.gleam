//// bankai — content-addressed task memory for distributed AI agents.
////
//// This root module owns the process entry point (`main`). `cli`, `socket`,
//// `mcp`, and `sync_peer` are kept separate so the protocol/CLI surface stays
//// pure and testable; none of them import this root.

import bankai/cli
import bankai/mcp
import bankai/platform_profile
import bankai/socket
import bankai/sync_peer
import bankai/version
import gleam/io

pub const version = version.current

pub fn version_string() -> String {
  version
}

/// Entry point for `gleam run -m bankai -- <args>` / the `bankai` escript.
pub fn main() -> Nil {
  let args = argv()
  case args {
    // Long-running servers — block, no single-shot envelope.
    ["serve", ..] ->
      case platform_profile.load(cli.default_workspace) {
        Ok(profile) ->
          case profile.mode {
            platform_profile.Local -> socket.serve(cli.default_workspace)
            platform_profile.Clustered ->
              socket.serve_clustered(cli.default_workspace)
          }
        Error(message) -> io.println(cli.error_envelope(message))
      }
    ["mcp", ..] -> mcp.serve(cli.default_workspace)
    ["sync-serve", ..rest] ->
      sync_peer.serve(
        cli.default_workspace,
        sync_peer.parse_port(rest, sync_peer.default_port),
      )
    [] -> io.println(cli.usage())
    [method, ..params] -> {
      // Mutation is daemon-only. Falling back to JSONL here would reinstate the
      // lost-update race that Mnesia is meant to remove.
      let request = daemon_request(method, params)
      case request {
        Error(message) -> io.println(cli.error_envelope(message))
        Ok(#(daemon_method, daemon_params)) ->
          case
            socket.client_request(
              cli.default_workspace,
              daemon_method,
              daemon_params,
            )
          {
            Ok(out) -> io.println(out)
            Error(_) ->
              case is_mutation(method, params) {
                True ->
                  io.println(cli.error_envelope(
                    "bankai daemon required for mutations; run bankai serve",
                  ))
                False ->
                  case is_task_operation(method, params) {
                    True ->
                      io.println(cli.error_envelope(
                        "bankai daemon required for task operations; run bankai serve",
                      ))
                    False -> io.println(cli.run_in(cli.default_workspace, args))
                  }
              }
          }
      }
    }
  }
}

@external(erlang, "bankai_argv_ffi", "get_args")
fn argv() -> List(String)

fn daemon_request(
  method: String,
  params: List(String),
) -> Result(#(String, List(String)), String) {
  case method, params {
    "prime", ["--query", query, ..] -> Ok(#("prime_query", [query]))
    "auth", ["mint", role, ..rest] -> Ok(#("auth_mint", [role, ..rest]))
    "auth", _ -> Error("usage: auth mint <read|write|admin> [--ttl seconds]")
    "merge", [source_id, canonical_id, ..] ->
      Ok(#("merge", [source_id, canonical_id]))
    "merge", _ -> Error("usage: merge <duplicate-id> <canonical-id>")
    "dep", ["add", task_id, target_id, ..rest] ->
      Ok(#("dep_add", [task_id, target_id, ..rest]))
    "dep", ["list", task_id, ..] -> Ok(#("dep_list", [task_id]))
    "dep", ["tree", task_id, ..] -> Ok(#("dep_tree", [task_id]))
    "dep", _ ->
      Error("usage: dep add|list|tree <task-id> [target-id] [--type T]")
    "cluster-status", _ -> Ok(#("cluster_status", []))
    "cluster_status", _ -> Ok(#("cluster_status", []))
    _, _ -> Ok(#(method, params))
  }
}

fn is_task_operation(method: String, params: List(String)) -> Bool {
  case method, params {
    "doctor", _ -> True
    "cluster-status", _ -> True
    "cluster_status", _ -> True
    "dep", ["list", ..] -> True
    "dep", ["tree", ..] -> True
    "ready", _ -> True
    "list", _ -> True
    "count", _ -> True
    "blocked", _ -> True
    "cycles", _ -> True
    "duplicates", _ -> True
    "stale", _ -> True
    "history", _ -> True
    "analytics", _ -> True
    "search", _ -> True
    "show", _ -> True
    "epic", _ -> True
    "inspect", _ -> True
    "prime", ["--query", ..] -> True
    _, _ -> is_mutation(method, params)
  }
}

fn is_mutation(method: String, params: List(String)) -> Bool {
  case method, params {
    "backup", _ -> True
    "export", _ -> True
    "import", _ -> True
    "sync", _ -> True
    "sync-pull", _ -> True
    "create", _ -> True
    "dep", ["add", ..] -> True
    "update", _ -> True
    _, _ -> False
  }
}
