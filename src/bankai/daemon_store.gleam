//// Daemon-owned transactional command service facade.
////
//// High-cohesion entry point aggregating mutations, queries, relations, diagnostics,
//// and subsystem services.

import bankai/backup
import bankai/compact
import bankai/daemon_store/diagnostics
import bankai/daemon_store/mutations
import bankai/daemon_store/queries
import bankai/daemon_store/relations
import bankai/gate_wisp/store as gate_wisp_store
import bankai/gates/service as gate_service
import bankai/memory
import bankai/mnesia_store
import bankai/molecules/service as molecule_service
import bankai/projections
import bankai/rules/service as rule_service
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync_peer
import bankai/task_lifecycle
import bankai/time
import bankai/types.{Wisp}
import bankai/wisps/service as wisp_service
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result

pub type Claimed =
  mutations.Claimed

// --- Lifecycle & Initialization ---

pub fn boot(workspace: String) -> Result(Nil, String) {
  mnesia_store.init(workspace)
  |> result.try(fn(_) { gate_wisp_store.init(workspace) })
  |> result.try(fn(_) {
    jsonl.load(from: workspace <> "/tasks.jsonl")
    |> result.try(fn(tasks) {
      mnesia_store.import_legacy_if_needed(workspace, store.from_list(tasks))
    })
  })
  |> result.try(fn(_) { projections.start_runtime(workspace) })
}

pub fn init_workspace(workspace: String) -> Result(json.Json, String) {
  boot(workspace)
  |> result.map(fn(_) { json.string("initialized bankai workspace") })
}

pub fn status(workspace: String) -> Result(json.Json, String) {
  diagnostics.doctor(workspace)
}

pub fn doctor(workspace: String) -> Result(json.Json, String) {
  diagnostics.doctor(workspace)
}

pub fn cluster_status(workspace: String) -> Result(json.Json, String) {
  diagnostics.cluster_status(workspace)
}

pub fn vector_projection_status(
  workspace: String,
) -> Result(json.Json, String) {
  diagnostics.vector_projection_status(workspace)
}

// --- Mutations ---

pub fn create(
  workspace: String,
  title: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mutations.create(workspace, title, rest)
}

pub fn update(
  workspace: String,
  id: String,
  status: String,
) -> Result(json.Json, String) {
  mutations.update(workspace, id, status)
}

pub fn update_fenced(
  workspace: String,
  id: String,
  status: String,
  fence_text: String,
) -> Result(json.Json, String) {
  mutations.update_fenced(workspace, id, status, fence_text)
}

pub fn claim_next_ready(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mutations.claim_next_ready(workspace, rest)
}

pub fn claim(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mutations.claim(workspace, id, rest)
}

pub fn claim_record(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(Claimed, String) {
  mutations.claim_record(workspace, id, rest)
}

pub fn release(workspace: String, id: String) -> Result(json.Json, String) {
  mutations.release(workspace, id)
}

pub fn reopen(workspace: String, id: String) -> Result(json.Json, String) {
  mutations.reopen(workspace, id)
}

pub fn undefer(workspace: String, id: String) -> Result(json.Json, String) {
  mutations.undefer(workspace, id)
}

pub fn defer_until(
  workspace: String,
  id: String,
  until_text: String,
) -> Result(json.Json, String) {
  mutations.defer_until(workspace, id, until_text)
}

pub fn close(
  workspace: String,
  id: String,
  reason: String,
) -> Result(json.Json, String) {
  mutations.close(workspace, id, reason)
}

pub fn add_label(
  workspace: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  mutations.add_label(workspace, id, label)
}

pub fn remove_label(
  workspace: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  mutations.remove_label(workspace, id, label)
}

pub fn set_priority(
  workspace: String,
  id: String,
  priority_text: String,
) -> Result(json.Json, String) {
  mutations.set_priority(workspace, id, priority_text)
}

pub fn merge(
  workspace: String,
  source_id: String,
  canonical_id: String,
) -> Result(json.Json, String) {
  mutations.merge(workspace, source_id, canonical_id)
}

pub fn batch_mutate(
  workspace: String,
  idempotency_key: String,
  mutations: List(String),
) -> Result(json.Json, String) {
  task_lifecycle.batch(workspace, idempotency_key, mutations)
}

pub fn satisfy_gate(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  mutations.satisfy_gate(workspace, id)
}

// --- Queries ---

pub fn list_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.list_tasks(workspace, rest)
}

pub fn ready_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.ready_tasks(workspace, rest)
}

pub fn show_task(workspace: String, id: String) -> Result(json.Json, String) {
  queries.show_task(workspace, id)
}

pub fn count_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.count_tasks(workspace, rest)
}

pub fn blocked_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.blocked_tasks(workspace, rest)
}

pub fn cycle_edges(workspace: String) -> Result(json.Json, String) {
  queries.cycle_edges(workspace)
}

pub fn duplicate_pairs(workspace: String) -> Result(json.Json, String) {
  queries.duplicate_pairs(workspace)
}

pub fn stale_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.stale_tasks(workspace, rest)
}

pub fn history(workspace: String, id: String) -> Result(json.Json, String) {
  queries.history(workspace, id)
}

pub fn analytics(workspace: String) -> Result(json.Json, String) {
  queries.analytics(workspace)
}

pub fn search(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.search(workspace, rest)
}

pub fn semantic_duplicates(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  queries.semantic_duplicates(workspace, rest)
}

pub fn inspect(workspace: String, hash: String) -> Result(json.Json, String) {
  queries.inspect(workspace, hash)
}

pub fn prime_query(
  workspace: String,
  query: String,
) -> Result(json.Json, String) {
  queries.prime_query(workspace, query)
}

pub fn epic(workspace: String, id: String) -> Result(json.Json, String) {
  queries.epic(workspace, id)
}

// --- Relations ---

pub fn add_dependency(
  workspace: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  relations.add_dependency(workspace, task_id, target_id, rest)
}

pub fn remove_dependency(
  workspace: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  relations.remove_dependency(workspace, task_id, target_id, rest)
}

pub fn dependency_list(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  relations.dependency_list(workspace, id)
}

pub fn dependency_tree(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  relations.dependency_tree(workspace, id)
}

pub fn traverse_dependencies(
  workspace: String,
  id: String,
  args: List(String),
) -> Result(json.Json, String) {
  relations.traverse_dependencies(workspace, id, args)
}

pub fn dependency_graph(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  relations.dependency_graph(workspace, args)
}

pub fn dependency_integrity(workspace: String) -> Result(json.Json, String) {
  relations.dependency_integrity(workspace)
}

// --- Memory & Interchange ---

pub fn remember(workspace: String, text: String) -> Result(json.Json, String) {
  memory.remember(workspace, text) |> result.map(memory.memory_to_json)
}

pub fn memories(workspace: String) -> Result(json.Json, String) {
  memory.all(workspace)
  |> result.map(fn(items) { json.array(items, of: memory.memory_to_json) })
}

pub fn compact(workspace: String) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.try(fn(before) {
    export_jsonl(workspace)
    |> result.try(fn(_) {
      let message = compact.run(workspace, workspace <> "/tasks.jsonl")
      jsonl.load(from: workspace <> "/tasks.jsonl")
      |> result.try(fn(tasks) {
        before
        |> list.filter(fn(task) { task.kind == Wisp })
        |> list.append(tasks)
        |> store.from_list()
        |> mnesia_store.replace_current_snapshot(workspace, _)
      })
      |> result.map(fn(_) { json.string(message) })
    })
  })
}

pub fn export_jsonl_to(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  mnesia_store.exportable_versions(workspace)
  |> result.try(fn(versions) {
    case jsonl.flush(store.list(versions), to: path) {
      Ok(_) -> Ok(json.string("exported immutable task history to " <> path))
      Error(_) -> Error("export failed: could not write " <> path)
    }
  })
}

pub fn export_jsonl(workspace: String) -> Result(json.Json, String) {
  export_jsonl_to(workspace, workspace <> "/tasks.jsonl")
}

pub fn backup_jsonl(workspace: String) -> Result(json.Json, String) {
  mnesia_store.exportable_versions(workspace)
  |> result.try(fn(versions) {
    let path = workspace <> "/tasks.jsonl.bak." <> int.to_string(time.now())
    case jsonl.flush(store.list(versions), to: path) {
      Ok(_) -> Ok(json.string("backed up Mnesia history to " <> path))
      Error(_) -> Error("backup failed: could not write " <> path)
    }
  })
}

pub fn import_jsonl(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  jsonl.load(from: path)
  |> result.try(fn(tasks) {
    mnesia_store.import_snapshot(workspace, store.from_list(tasks))
  })
  |> result.map(fn(_) { json.string("imported tasks from " <> path) })
}

// --- Subsystem Delegations (Backup, Conflicts, Journal, Gates, Wisps, Molecules, Rules) ---

pub fn backup_list(workspace: String) -> Result(json.Json, String) {
  backup.catalog(workspace)
  |> result.map(fn(entries) {
    json.array(entries, fn(e) {
      json.object([
        #("path", json.string(e.path)),
        #("task_count", json.int(e.task_count)),
        #("valid", json.bool(e.valid)),
      ])
    })
  })
}

pub fn backup_preview(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  backup.divergence_detail(workspace, path)
  |> result.map(fn(div) {
    json.object([
      #("current_count", json.int(div.current_count)),
      #("backup_count", json.int(div.backup_count)),
      #("same_tasks", json.int(div.same_tasks)),
      #(
        "added_in_backup",
        json.array(div.added_in_backup, fn(id) { json.string(id) }),
      ),
      #(
        "missing_in_backup",
        json.array(div.missing_in_backup, fn(id) { json.string(id) }),
      ),
      #(
        "modified_in_backup",
        json.array(div.modified_in_backup, fn(id) { json.string(id) }),
      ),
    ])
  })
}

pub fn backup_restore(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  backup.restore(workspace, path)
  |> result.map(fn(_) { json.string("restored backup from " <> path) })
}

pub fn backup_prune(workspace: String, keep: Int) -> Result(json.Json, String) {
  backup.prune(workspace, keep: keep)
  |> result.map(fn(count) {
    json.object([
      #("pruned_count", json.int(count)),
      #("kept", json.int(keep)),
    ])
  })
}

pub fn conflicts_list(workspace: String) -> Result(json.Json, String) {
  sync_peer.list_conflicts(workspace)
  |> result.map(fn(conflicts) {
    json.array(conflicts, fn(c) {
      json.object([
        #("id", json.string(c.id)),
        #("timestamp", json.int(c.timestamp)),
        #("author", json.string(c.author)),
        #("detail", json.string(c.detail)),
      ])
    })
  })
}

pub fn conflicts_resolve(
  workspace: String,
  conflict_id: String,
) -> Result(json.Json, String) {
  sync_peer.resolve_conflict(workspace, conflict_id)
  |> result.map(fn(_) { json.string("resolved conflict " <> conflict_id) })
}

pub fn conflicts_clear(workspace: String) -> Result(json.Json, String) {
  sync_peer.clear_conflicts(workspace)
  |> result.map(fn(_) { json.string("cleared all replication conflicts") })
}

pub fn journal_tail(
  workspace: String,
  after_offset: Int,
) -> Result(json.Json, String) {
  mnesia_store.change_tail(workspace, after_offset)
  |> result.map(fn(events) {
    json.object([
      #("after_offset", json.int(after_offset)),
      #("count", json.int(list.length(events))),
      #("events", json.array(events, fn(e) { json.string(e) })),
    ])
  })
}

pub fn gate_list(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  gate_service.list(workspace, rest)
}

pub fn gate_show(workspace: String, id: String) -> Result(json.Json, String) {
  gate_service.show(workspace, id)
}

pub fn gate_check(workspace: String, id: String) -> Result(json.Json, String) {
  gate_service.check(workspace, id)
}

pub fn gate_resolve(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  gate_service.resolve(workspace, id, rest)
}

pub fn gate_fact_ingest(
  workspace: String,
  gate_id: String,
  issuer: String,
  wire: String,
) -> Result(json.Json, String) {
  gate_service.ingest_fact(workspace, gate_id, issuer, wire)
}

pub fn wisp_list(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  wisp_service.list(workspace, rest)
}

pub fn wisp_promote(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  wisp_service.promote(workspace, id, rest)
}

pub fn wisp_digest(workspace: String, id: String) -> Result(json.Json, String) {
  wisp_service.digest(workspace, id)
}

pub fn wisp_burn(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  wisp_service.burn(workspace, id, rest)
}

pub fn wisp_gc(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  wisp_service.gc(workspace, rest)
}

pub fn wisp_archive(
  workspace: String,
  id: option.Option(String),
) -> Result(json.Json, String) {
  wisp_service.archives(workspace, option.unwrap(id, ""))
}

pub fn molecule_register(
  workspace: String,
  source: String,
) -> Result(json.Json, String) {
  molecule_service.register(workspace, source)
}

pub fn molecule_list(workspace: String) -> Result(json.Json, String) {
  molecule_service.list(workspace)
}

pub fn molecule_show(
  workspace: String,
  hash: String,
) -> Result(json.Json, String) {
  molecule_service.show(workspace, hash)
}

pub fn molecule_instantiate(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
  raw_bindings: List(String),
) -> Result(json.Json, String) {
  molecule_service.instantiate(
    workspace,
    template_hash,
    idempotency_key,
    raw_bindings,
  )
}

pub fn rule_register(
  workspace: String,
  name: String,
  source: String,
) -> Result(json.Json, String) {
  rule_service.register(workspace, name, source)
}

pub fn rule_list(workspace: String) -> Result(json.Json, String) {
  rule_service.list(workspace)
}

pub fn rule_show(workspace: String, hash: String) -> Result(json.Json, String) {
  rule_service.show(workspace, hash)
}

pub fn rule_approve(
  workspace: String,
  hash: String,
) -> Result(json.Json, String) {
  rule_service.approve(workspace, hash)
}

pub fn rule_eval(
  workspace: String,
  hash: String,
  args: List(String),
) -> Result(json.Json, String) {
  rule_service.evaluate(workspace, hash, args)
}

pub fn rule_audit(workspace: String) -> Result(json.Json, String) {
  rule_service.audits(workspace, "")
}

pub fn merge_duplicate(
  workspace: String,
  source_id: String,
  canonical_id: String,
) -> Result(json.Json, String) {
  mutations.merge(workspace, source_id, canonical_id)
}

pub fn pull_peer(
  workspace: String,
  host: String,
  port: Int,
) -> Result(json.Json, String) {
  sync_peer.fetch(host, port, workspace)
  |> result.try(fn(snapshot) {
    mnesia_store.import_replica_snapshot(
      workspace,
      store.from_list(snapshot.versions),
      snapshot.heads,
    )
  })
  |> result.map(fn(_) {
    json.string(
      "reconciled transactional store with peer at "
      <> host
      <> ":"
      <> int.to_string(port),
    )
  })
}

pub fn reconcile_jsonl(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  jsonl.load(from: path)
  |> result.try(fn(tasks) {
    mnesia_store.import_snapshot(workspace, store.from_list(tasks))
  })
  |> result.map(fn(_) {
    json.string("reconciled external snapshot from " <> path)
  })
}
