//// The daemon request router: one method, one handler, one result.
//// Pure data in, Result(json.Json, String) out — no transport knowledge.

import bankai/cli
import bankai/cli/parser
import bankai/daemon_store
import bankai/gates/service as gate_service
import bankai/molecules/service as molecule_service
import bankai/rules/service as rule_service
import bankai/service_auth
import bankai/socket_route_update
import bankai/sync/trust_args
import bankai/wisps/service as wisp_service
import gleam/int
import gleam/json
import gleam/result

pub fn route(
  workspace: String,
  method: String,
  params: List(String),
) -> Result(json.Json, String) {
  case method {
    "ready" ->
      case params {
        ["--claim", ..rest] ->
          daemon_result(daemon_store.claim_next_ready(workspace, rest))
        _ -> daemon_result(daemon_store.ready_tasks(workspace, params))
      }

    "list" -> daemon_result(daemon_store.list_tasks(workspace, params))
    "reclaim" -> daemon_result(daemon_store.reclaim_expired(workspace))
    "create" ->
      case parser.parse_create_args(params) {
        Error(e) -> Error(e)
        Ok(parsed) -> {
          // Strip the title token(s) but pass every other flag through raw:
          // gate/wisp handlers downstream still read the original argv.
          let rest = case params {
            ["--title", _, ..r] -> r
            [_, ..r] -> r
            [] -> []
          }
          daemon_result(daemon_store.create(workspace, parsed.title, rest))
        }
      }
    "update" ->
      case parser.parse_update_args(params) {
        Error(e) -> Error(e)
        Ok(parsed) -> socket_route_update.route_update(workspace, parsed)
      }
    "batch" ->
      case params {
        ["--idempotency-key", key, ..mutations] ->
          daemon_result(daemon_store.batch_mutate(workspace, key, mutations))
        _ -> Error("batch requires --idempotency-key <key> <mutation>...")
      }
    "merge" ->
      case params {
        [source_id, canonical_id, ..] ->
          daemon_result(daemon_store.merge_duplicate(
            workspace,
            source_id,
            canonical_id,
          ))
        _ -> Error("merge requires <source-id> <canonical-id>")
      }
    "dep_add" ->
      case params {
        [task_id, target_id, ..rest] ->
          daemon_result(daemon_store.add_dependency(
            workspace,
            task_id,
            target_id,
            rest,
          ))
        _ -> Error("dep_add requires <task-id> <target-id>")
      }
    "dep_remove" ->
      case params {
        [task_id, target_id, ..rest] ->
          daemon_result(daemon_store.remove_dependency(
            workspace,
            task_id,
            target_id,
            rest,
          ))
        _ -> Error("dep_remove requires <task-id> <target-id>")
      }
    "dep_list" ->
      case params {
        [id, ..] -> daemon_result(daemon_store.dependency_list(workspace, id))
        _ -> Error("dep_list requires <task-id>")
      }
    "dep_tree" ->
      case params {
        [id, ..] -> daemon_result(daemon_store.dependency_tree(workspace, id))
        _ -> Error("dep_tree requires <task-id>")
      }
    "dep_traverse" ->
      case params {
        [id, ..rest] ->
          daemon_result(daemon_store.traverse_dependencies(workspace, id, rest))
        _ -> Error("dep_traverse requires <task-id>")
      }
    "dep_graph" ->
      daemon_result(daemon_store.dependency_graph(workspace, params))
    "dep_check" -> daemon_result(daemon_store.dependency_integrity(workspace))
    "doctor" -> daemon_result(daemon_store.doctor(workspace))
    "cluster_status" -> daemon_result(daemon_store.cluster_status(workspace))
    "backup" -> daemon_result(daemon_store.backup_jsonl(workspace))
    "backup_list" -> daemon_result(daemon_store.backup_list(workspace))
    "backup_preview" ->
      case params {
        [path, ..] ->
          daemon_result(daemon_store.backup_preview(workspace, path))
        _ -> Error("backup_preview requires <path>")
      }
    "backup_restore" ->
      case params {
        [path, ..] ->
          daemon_result(daemon_store.backup_restore(workspace, path))
        _ -> Error("backup_restore requires <path>")
      }
    "backup_prune" ->
      case params {
        ["--keep", keep_text, ..] ->
          case int.parse(keep_text) {
            Ok(k) -> daemon_result(daemon_store.backup_prune(workspace, k))
            Error(_) -> Error("keep must be an integer")
          }
        [keep_text, ..] ->
          case int.parse(keep_text) {
            Ok(k) -> daemon_result(daemon_store.backup_prune(workspace, k))
            Error(_) -> Error("keep must be an integer")
          }
        _ -> daemon_result(daemon_store.backup_prune(workspace, 5))
      }
    "sync_conflicts" -> daemon_result(daemon_store.conflicts_list(workspace))
    "sync_conflict_resolve" ->
      case params {
        [id, "--keep", side, ..] ->
          daemon_result(daemon_store.conflicts_resolve(workspace, id, side))
        [_id, ..] ->
          Error(
            "sync_conflict_resolve requires <conflict-id> --keep local|remote",
          )
        _ ->
          Error(
            "sync_conflict_resolve requires <conflict-id> --keep local|remote",
          )
      }
    "sync_conflict_clear" ->
      daemon_result(daemon_store.conflicts_clear(workspace))
    "sync_identity" -> daemon_result(daemon_store.sync_identity(workspace))
    "sync_trust" ->
      case params {
        [key, ..rest] ->
          case trust_args.expiry_args(rest) {
            Ok(expires_at) ->
              daemon_result(daemon_store.sync_trust_for(
                workspace,
                key,
                expires_at,
              ))
            Error(message) -> Error(message)
          }
        _ -> Error("sync_trust requires <public-key>")
      }
    "sync_revoke" ->
      case params {
        [key, ..] -> daemon_result(daemon_store.sync_revoke(workspace, key))
        _ -> Error("sync_revoke requires <public-key>")
      }
    "sync_rotate" ->
      case params {
        [old_id, new_id, ..rest] ->
          case trust_args.rotation_args(rest) {
            Ok(#(overlap, expires_at)) ->
              daemon_result(daemon_store.sync_rotate(
                workspace,
                old_id,
                new_id,
                overlap,
                expires_at,
              ))
            Error(message) -> Error(message)
          }
        _ ->
          Error(
            "sync_rotate requires <old-key> <new-key> [--overlap NS] [--expires-at NS]",
          )
      }
    "journal_tail" ->
      case params {
        ["--after", offset_text, ..] ->
          case int.parse(offset_text) {
            Ok(offset) ->
              daemon_result(daemon_store.journal_tail(workspace, offset))
            Error(_) -> Error("after offset must be an integer")
          }
        [offset_text, ..] ->
          case int.parse(offset_text) {
            Ok(offset) ->
              daemon_result(daemon_store.journal_tail(workspace, offset))
            Error(_) -> Error("offset must be an integer")
          }
        [] -> daemon_result(daemon_store.journal_tail(workspace, -1))
      }
    "export" -> daemon_result(daemon_store.export_jsonl(workspace))
    "import" ->
      case params {
        [path, ..] -> daemon_result(daemon_store.import_jsonl(workspace, path))
        _ -> Error("import requires <path>")
      }
    "sync_pull" ->
      case params {
        ["--host", host, "--port", port_text, ..] ->
          case int.parse(port_text) {
            Ok(port) ->
              daemon_result(daemon_store.pull_peer(workspace, host, port))
            Error(_) -> Error("sync_pull port must be an integer")
          }
        ["--host", host, ..] ->
          daemon_result(daemon_store.pull_peer(workspace, host, 7654))
        _ -> Error("sync_pull requires --host <host> [--port <n>]")
      }
    "remember" ->
      case params {
        [text, ..] -> daemon_result(daemon_store.remember(workspace, text))
        _ -> Error("remember requires an insight")
      }
    "memories" -> daemon_result(daemon_store.memories(workspace))
    "compact" -> daemon_result(daemon_store.compact(workspace))
    "show" ->
      case params {
        [id, ..] -> daemon_result(daemon_store.show_task(workspace, id))
        _ -> Error("show requires <id>")
      }
    "count" -> daemon_result(daemon_store.count_tasks(workspace, params))
    "blocked" -> daemon_result(daemon_store.blocked_tasks(workspace, params))
    "cycles" -> daemon_result(daemon_store.cycle_edges(workspace))
    "duplicates" ->
      case params {
        ["--semantic", ..rest] ->
          daemon_result(daemon_store.semantic_duplicates(workspace, rest))
        _ -> daemon_result(daemon_store.duplicate_pairs(workspace))
      }
    "stale" -> daemon_result(daemon_store.stale_tasks(workspace, params))
    "history" ->
      case params {
        [id, ..] -> daemon_result(daemon_store.history(workspace, id))
        _ -> Error("history requires <id>")
      }
    "analytics" -> daemon_result(daemon_store.analytics(workspace))
    "search" -> daemon_result(daemon_store.search(workspace, params))
    "prime_query" ->
      case params {
        [query, ..] -> daemon_result(daemon_store.prime_query(workspace, query))
        _ -> Error("prime_query requires <query>")
      }
    "epic" ->
      case params {
        [id, ..] -> daemon_result(daemon_store.epic(workspace, id))
        _ -> Error("epic requires <id>")
      }
    "inspect" ->
      case params {
        [hash, ..] -> daemon_result(daemon_store.inspect(workspace, hash))
        _ -> Error("inspect requires <hash>")
      }
    "sync" ->
      case params {
        ["--from", path, ..] ->
          daemon_result(daemon_store.reconcile_jsonl(workspace, path))
        _ -> Error("sync requires --from <path>")
      }
    "init" ->
      case daemon_store.boot(workspace) {
        Ok(_) -> Ok(json.string(cli.run_in(workspace, ["init"])))
        Error(message) -> Error(message)
      }
    "auth_mint" ->
      case params {
        [role, "--ttl", ttl_text] ->
          case int.parse(ttl_text) {
            Ok(ttl) ->
              daemon_result(
                service_auth.mint(workspace, role, ttl)
                |> result.map(json.string),
              )
            Error(_) -> Error("auth ttl must be an integer")
          }
        [role] ->
          daemon_result(
            service_auth.mint_default(workspace, role)
            |> result.map(json.string),
          )
        _ -> Error("auth_mint requires <read|write|admin> [--ttl seconds]")
      }
    "gate_list" -> daemon_result(gate_service.list(workspace, params))
    "gate_show" ->
      case params {
        [id, ..] -> daemon_result(gate_service.show(workspace, id))
        _ -> Error("gate_show requires <gate-id>")
      }
    "gate_check" ->
      case params {
        [id, ..] -> daemon_result(gate_service.check(workspace, id))
        _ -> Error("gate_check requires <gate-id>")
      }
    "gate_resolve" ->
      case params {
        [id, ..rest] -> daemon_result(gate_service.resolve(workspace, id, rest))
        _ -> Error("gate_resolve requires <gate-id>")
      }
    "gate_fact_ingest" ->
      case params {
        [id, "--issuer", issuer, "--wire", wire, ..] ->
          daemon_result(gate_service.ingest_fact(workspace, id, issuer, wire))
        _ ->
          Error(
            "gate_fact_ingest requires <gate-id> --issuer <public-key> --wire <json>",
          )
      }
    "wisp_list" -> daemon_result(wisp_service.list(workspace, params))
    "wisp_promote" ->
      case params {
        [id, ..rest] -> daemon_result(wisp_service.promote(workspace, id, rest))
        _ -> Error("wisp_promote requires <wisp-id>")
      }
    "wisp_digest" ->
      case params {
        [id, ..] -> daemon_result(wisp_service.digest(workspace, id))
        _ -> Error("wisp_digest requires <wisp-id>")
      }
    "wisp_burn" ->
      case params {
        [id, ..rest] -> daemon_result(wisp_service.burn(workspace, id, rest))
        _ -> Error("wisp_burn requires <wisp-id>")
      }
    "wisp_gc" -> daemon_result(wisp_service.gc(workspace, params))
    "wisp_archive" ->
      case params {
        [] -> daemon_result(wisp_service.archives(workspace, ""))
        [id, ..] -> daemon_result(wisp_service.archives(workspace, id))
      }
    "molecule_register" ->
      case params {
        [source, ..] ->
          daemon_result(molecule_service.register(workspace, source))
        _ -> Error("molecule_register requires <template-json>")
      }
    "molecule_list" -> daemon_result(molecule_service.list(workspace))
    "molecule_show" ->
      case params {
        [hash, ..] -> daemon_result(molecule_service.show(workspace, hash))
        _ -> Error("molecule_show requires <template-hash>")
      }
    "molecule_instantiate" ->
      case params {
        [hash, "--idempotency-key", key, ..bindings] ->
          daemon_result(molecule_service.instantiate(
            workspace,
            hash,
            key,
            bindings,
          ))
        _ ->
          Error(
            "molecule_instantiate requires <hash> --idempotency-key <key> [name=value]...",
          )
      }
    "molecule_compose" ->
      case params {
        [name, left, right, ..] ->
          daemon_result(molecule_service.compose(workspace, name, left, right))
        _ -> Error("molecule_compose requires <name> <left-hash> <right-hash>")
      }
    "molecule_instance" ->
      case params {
        [id, ..] -> daemon_result(molecule_service.instance(workspace, id))
        _ -> Error("molecule_instance requires <instance-id>")
      }
    "molecule_provenance" ->
      case params {
        [id, ..] -> daemon_result(molecule_service.provenance(workspace, id))
        _ -> Error("molecule_provenance requires <task-id>")
      }
    "molecule_progress" ->
      case params {
        [id, ..] -> daemon_result(molecule_service.progress(workspace, id))
        _ -> Error("molecule_progress requires <instance-id>")
      }
    "molecule_current" ->
      case params {
        [id, ..] -> daemon_result(molecule_service.current(workspace, id))
        _ -> Error("molecule_current requires <instance-id>")
      }
    "molecule_distill" ->
      case params {
        [id, ..] -> daemon_result(molecule_service.distill(workspace, id))
        _ -> Error("molecule_distill requires <instance-id>")
      }
    "rule_register" ->
      case params {
        [name, source, ..] ->
          daemon_result(rule_service.register(workspace, name, source))
        _ -> Error("rule_register requires <name> <source>")
      }
    "rule_list" -> daemon_result(rule_service.list(workspace))
    "rule_show" ->
      case params {
        [hash, ..] -> daemon_result(rule_service.show(workspace, hash))
        _ -> Error("rule_show requires <hash>")
      }
    "rule_approve" ->
      case params {
        [hash, ..] -> daemon_result(rule_service.approve(workspace, hash))
        _ -> Error("rule_approve requires <hash>")
      }
    "rule_revoke" ->
      case params {
        [hash, ..] -> daemon_result(rule_service.revoke(workspace, hash))
        _ -> Error("rule_revoke requires <hash>")
      }
    "rule_eval" ->
      case params {
        [hash, ..rest] ->
          daemon_result(rule_service.evaluate(workspace, hash, rest))
        _ -> Error("rule_eval requires <hash> [--caller <name>] [--task <id>]")
      }
    "rule_audit" ->
      case params {
        [] -> daemon_result(rule_service.audits(workspace, ""))
        [hash, ..] -> daemon_result(rule_service.audits(workspace, hash))
      }
    _ -> Error("unknown method: " <> method)
  }
}

fn daemon_result(
  result: Result(json.Json, String),
) -> Result(json.Json, String) {
  result
}
