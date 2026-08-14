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
import gleam/list

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
    "gate", ["list", ..rest] -> Ok(#("gate_list", rest))
    "gate", ["show", id, ..] -> Ok(#("gate_show", [id]))
    "gate", ["check", id, ..] -> Ok(#("gate_check", [id]))
    "gate", ["resolve", id, ..rest] -> Ok(#("gate_resolve", [id, ..rest]))
    "gate", ["fact", "ingest", id, "--issuer", issuer, "--wire", wire, ..] ->
      Ok(#("gate_fact_ingest", [id, "--issuer", issuer, "--wire", wire]))
    "gate", _ ->
      Error("usage: gate list|show|check|resolve|fact ingest <gate-id>")
    "wisp", ["list", ..rest] -> Ok(#("wisp_list", rest))
    "wisp", ["create", title, ..rest] ->
      Ok(#("create", [title, "--kind", "wisp", ..rest]))
    "wisp", ["promote", id, ..rest] -> Ok(#("wisp_promote", [id, ..rest]))
    "wisp", ["digest", id, ..] -> Ok(#("wisp_digest", [id]))
    "wisp", ["squash", id, ..] -> Ok(#("wisp_digest", [id]))
    "wisp", ["burn", id, ..rest] -> Ok(#("wisp_burn", [id, ..rest]))
    "wisp", ["gc", ..rest] -> Ok(#("wisp_gc", rest))
    "wisp", ["archive", id, ..] -> Ok(#("wisp_archive", [id]))
    "wisp", ["archive", ..] -> Ok(#("wisp_archive", []))
    "wisp", _ ->
      Error("usage: wisp list|create|promote|digest|squash|burn|gc|archive")
    "molecule", ["register", source, ..] -> Ok(#("molecule_register", [source]))
    "molecule", ["list", ..] -> Ok(#("molecule_list", []))
    "molecule", ["show", hash, ..] -> Ok(#("molecule_show", [hash]))
    "molecule", ["instantiate", hash, "--idempotency-key", key, ..bindings] ->
      Ok(
        #("molecule_instantiate", [hash, "--idempotency-key", key, ..bindings]),
      )
    "molecule", ["compose", name, left, right, ..] ->
      Ok(#("molecule_compose", [name, left, right]))
    "molecule", ["instance", id, ..] -> Ok(#("molecule_instance", [id]))
    "molecule", ["provenance", id, ..] -> Ok(#("molecule_provenance", [id]))
    "molecule", ["progress", id, ..] -> Ok(#("molecule_progress", [id]))
    "molecule", ["current", id, ..] -> Ok(#("molecule_current", [id]))
    "molecule", ["distill", id, ..] -> Ok(#("molecule_distill", [id]))
    "molecule", _ ->
      Error(
        "usage: molecule register|list|show|instantiate|compose|instance|provenance|progress|current|distill",
      )
    "rule", ["register", name, source, ..] ->
      Ok(#("rule_register", [name, source]))
    "rule", ["list", ..] -> Ok(#("rule_list", []))
    "rule", ["show", hash, ..] -> Ok(#("rule_show", [hash]))
    "rule", ["approve", hash, ..] -> Ok(#("rule_approve", [hash]))
    "rule", ["revoke", hash, ..] -> Ok(#("rule_revoke", [hash]))
    "rule", ["eval", hash, ..rest] -> Ok(#("rule_eval", [hash, ..rest]))
    "rule", ["audit", hash, ..] -> Ok(#("rule_audit", [hash]))
    "rule", ["audit", ..] -> Ok(#("rule_audit", []))
    "rule", _ ->
      Error("usage: rule register|list|show|approve|revoke|eval|audit")
    "batch", ["--idempotency-key", key, ..mutations] ->
      Ok(#("batch", ["--idempotency-key", key, ..mutations]))
    "batch", _ -> Error("usage: batch --idempotency-key <key> <mutation>...")
    "merge", [source_id, canonical_id, ..] ->
      Ok(#("merge", [source_id, canonical_id]))
    "merge", _ -> Error("usage: merge <duplicate-id> <canonical-id>")
    "dep", ["add", task_id, target_id, ..rest] ->
      Ok(#("dep_add", [task_id, target_id, ..rest]))
    "dep", ["remove", task_id, target_id, ..rest] ->
      Ok(#("dep_remove", [task_id, target_id, ..rest]))
    "dep", ["list", task_id, ..rest] ->
      case
        list.contains(rest, "--direction")
        || list.contains(rest, "--depth")
        || list.contains(rest, "--type")
      {
        True -> Ok(#("dep_traverse", [task_id, ..rest]))
        False -> Ok(#("dep_list", [task_id, ..rest]))
      }
    "dep", ["tree", task_id, ..rest] ->
      Ok(#("dep_traverse", [task_id, "--direction", "outgoing", ..rest]))
    "dep", ["graph", ..rest] -> Ok(#("dep_graph", rest))
    "dep", ["check", ..] -> Ok(#("dep_check", []))
    "dep", _ ->
      Error(
        "usage: dep add|remove|list|tree|graph|check <task-id> [target-id] [--type T]",
      )
    "cluster-status", _ -> Ok(#("cluster_status", []))
    "cluster_status", _ -> Ok(#("cluster_status", []))
    _, _ -> Ok(#(method, params))
  }
}

fn is_task_operation(method: String, params: List(String)) -> Bool {
  case method, params {
    "doctor", _ -> True
    "gate", _ -> True
    "wisp", _ -> True
    "rule", _ -> True
    "molecule", _ -> True
    "cluster-status", _ -> True
    "cluster_status", _ -> True
    "dep", ["list", ..] -> True
    "dep", ["tree", ..] -> True
    "dep", ["graph", ..] -> True
    "dep", ["check", ..] -> True
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
    "gate", ["resolve", ..] -> True
    "gate", ["fact", "ingest", ..] -> True
    "wisp", ["create", ..] -> True
    "wisp", ["promote", ..] -> True
    "wisp", ["burn", ..] -> True
    "wisp", ["gc", ..] -> True
    "molecule", ["register", ..] -> True
    "molecule", ["instantiate", ..] -> True
    "molecule", ["compose", ..] -> True
    "batch", _ -> True
    "dep", ["add", ..] -> True
    "dep", ["remove", ..] -> True
    "update", _ -> True
    _, _ -> False
  }
}
