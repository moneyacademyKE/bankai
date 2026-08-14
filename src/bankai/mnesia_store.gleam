//// Bankai's narrow Mnesia repository boundary. Records are canonical JSON so
//// Gleam's Task layout never leaks into the persisted Erlang schema.

import bankai/ast_bridge
import bankai/gate_wisp/store as lifecycle_store
import bankai/serde
import bankai/storage/store
import bankai/sync/merge
import bankai/types.{type Task, Wisp}
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleamunison/identity

@external(erlang, "bankai_mnesia_ffi", "init")
fn ffi_init(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "reset_workspace")
fn ffi_reset_workspace(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "current_json")
fn ffi_current_json(workspace: String) -> Result(List(String), String)

@external(erlang, "bankai_mnesia_ffi", "versions_json")
fn ffi_versions_json(workspace: String) -> Result(List(String), String)

@external(erlang, "bankai_mnesia_ffi", "get_current")
fn ffi_get_current(workspace: String, id: String) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "put_new")
fn ffi_put_new(
  workspace: String,
  id: String,
  hash: String,
  json: String,
  operation: String,
) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "compare_and_put")
fn ffi_compare_and_put(
  workspace: String,
  id: String,
  expected_hash: String,
  hash: String,
  json: String,
  operation: String,
) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "compare_and_put_committed")
fn ffi_compare_and_put_committed(
  workspace: String,
  command_id: String,
  id: String,
  expected_hash: String,
  hash: String,
  json: String,
  operation: String,
) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "import_if_needed")
fn ffi_import_if_needed(
  workspace: String,
  versions: List(#(String, String, String)),
  current: List(#(String, String, String)),
) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "replace_many")
fn ffi_replace_many(
  workspace: String,
  rows: List(#(String, String, String, String)),
  operation: String,
) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "idempotent_result")
fn ffi_idempotent_result(
  workspace: String,
  idempotency_key: String,
  namespace: String,
) -> Result(Option(#(String, String)), String)

@external(erlang, "bankai_mnesia_ffi", "replace_many_idempotent")
fn ffi_replace_many_idempotent(
  workspace: String,
  idempotency_key: String,
  fingerprint: String,
  rows: List(#(String, String, String, String)),
) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "import_snapshot")
fn ffi_import_snapshot(
  workspace: String,
  versions: List(#(String, String, String)),
  current: List(#(String, String, String)),
) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "replace_current_snapshot")
fn ffi_replace_current_snapshot(
  workspace: String,
  current: List(#(String, String, String)),
) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "snapshot_json")
fn ffi_snapshot_json(workspace: String) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "projection_snapshot_rows")
fn ffi_projection_snapshot_rows(
  workspace: String,
) -> Result(#(Int, List(String)), String)

@external(erlang, "bankai_mnesia_ffi", "projection_checkpoint")
fn ffi_projection_checkpoint(
  workspace: String,
  projection: String,
) -> Result(Int, String)

@external(erlang, "bankai_mnesia_ffi", "set_projection_checkpoint")
fn ffi_set_projection_checkpoint(
  workspace: String,
  projection: String,
  offset: Int,
) -> Result(Nil, String)

@external(erlang, "bankai_changefeed_ffi", "tail_json")
fn ffi_change_tail_json(
  workspace: String,
  after: Int,
) -> Result(List(String), String)

pub fn init(workspace: String) -> Result(Nil, String) {
  ffi_init(workspace)
}

/// Scoped test harness cleanup. Never used by application commands; it clears
/// only this workspace's Mnesia rows so repeatable tests do not leak history.
pub fn reset_workspace_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_workspace(workspace)
  |> result.try(fn(_) { lifecycle_store.init(workspace) })
  |> result.try(fn(_) { lifecycle_store.reset_workspace_for_test(workspace) })
}

/// Lazily imports the legacy JSONL history exactly once. The version rows retain
/// every immutable hash; current rows are derived by the existing Store rules.
pub fn import_legacy_if_needed(
  workspace: String,
  legacy: store.Store,
) -> Result(Nil, String) {
  validated_rows(legacy)
  |> result.try(fn(rows) { ffi_import_if_needed(workspace, rows.0, rows.1) })
}

/// Import a portable JSONL snapshot. It validates every record before crossing
/// the FFI, unions versions by hash, and refuses same-ID head divergence rather
/// than silently choosing a winner.
pub fn import_replica_snapshot(
  workspace: String,
  versions: store.Store,
  heads: List(Task),
) -> Result(Nil, String) {
  validated_rows(versions)
  |> result.try(fn(rows) {
    heads
    |> list.try_map(ast_bridge.validate)
    |> result.try(fn(valid_heads) {
      current_store(workspace)
      |> result.try(fn(local) {
        let conflicts =
          merge.merge(store.current_tasks(local), valid_heads).conflicts
        case list.is_empty(conflicts) {
          True ->
            ffi_import_snapshot(
              workspace,
              rows.0,
              valid_heads
                |> list.map(fn(task) {
                  #(
                    task.id,
                    identity.hash_to_debug_string(task.content_hash),
                    serde.task_to_json_string(task),
                  )
                }),
            )
          False ->
            Error(
              "import rejected: divergent task heads require reconciliation",
            )
        }
      })
    })
  })
}

/// Import a portable JSONL snapshot, projecting its heads from the immutable
/// version set. Peer replication uses import_replica_snapshot so it never
/// loses the sender's explicit head view.
pub fn import_snapshot(
  workspace: String,
  incoming: store.Store,
) -> Result(Nil, String) {
  import_replica_snapshot(workspace, incoming, store.current_tasks(incoming))
}

fn validated_rows(
  index: store.Store,
) -> Result(
  #(List(#(String, String, String)), List(#(String, String, String))),
  String,
) {
  store.list(index)
  |> list.try_map(ast_bridge.validate)
  |> result.map(fn(_) { #(version_rows(index), current_rows(index)) })
}

fn version_rows(index: store.Store) -> List(#(String, String, String)) {
  store.list(index)
  |> list.map(fn(task) {
    #(
      task.id,
      identity.hash_to_debug_string(task.content_hash),
      serde.task_to_json_string(task),
    )
  })
}

fn current_rows(index: store.Store) -> List(#(String, String, String)) {
  store.current_tasks(index)
  |> list.map(fn(task) {
    #(
      task.id,
      identity.hash_to_debug_string(task.content_hash),
      serde.task_to_json_string(task),
    )
  })
}

/// Replace active heads after an explicit archival operation while retaining
/// all immutable versions for inspect/history. Inputs are validated before FFI.
pub fn replace_current_snapshot(
  workspace: String,
  current: store.Store,
) -> Result(Nil, String) {
  current
  |> store.list()
  |> list.try_map(ast_bridge.validate)
  |> result.try(fn(valid) {
    ffi_replace_current_snapshot(
      workspace,
      valid
        |> store.from_list()
        |> current_rows(),
    )
  })
}

pub fn exportable_versions(workspace: String) -> Result(store.Store, String) {
  version_store(workspace)
  |> result.map(fn(index) {
    index
    |> store.list()
    |> list.filter(fn(task) { task.kind != Wisp })
    |> store.from_list()
  })
}

pub fn current_store(workspace: String) -> Result(store.Store, String) {
  ffi_current_json(workspace)
  |> result.try(fn(rows) {
    rows
    |> list.try_map(serde.task_from_json_string)
    |> result.map(store.from_list)
  })
}

pub fn version_store(workspace: String) -> Result(store.Store, String) {
  ffi_versions_json(workspace)
  |> result.try(fn(rows) {
    rows
    |> list.try_map(serde.task_from_json_string)
    |> result.map(store.from_list)
  })
}

/// Returns canonical snapshot/tail JSON payloads for AaronDB adapters. The
/// payloads are already canonical bytes from the persistence boundary; callers
/// choose their own decoder without widening Bankai's authority surface.
pub fn projection_snapshot(workspace: String) -> Result(String, String) {
  ffi_snapshot_json(workspace)
}

/// Returns canonical committed change records after `offset`, in ascending
/// non-gapped workspace order. Event IDs make delivery replay-safe.
pub fn change_tail(
  workspace: String,
  offset: Int,
) -> Result(List(String), String) {
  ffi_change_tail_json(workspace, offset)
}

/// Typed current-head snapshot paired with its exact committed event watermark.
/// Unlike `projection_snapshot`, consumers never need to reparse the task JSON.
pub fn projection_snapshot_rows(
  workspace: String,
) -> Result(#(Int, List(Task)), String) {
  ffi_projection_snapshot_rows(workspace)
  |> result.try(fn(snapshot) {
    let #(offset, rows) = snapshot
    rows
    |> list.try_map(serde.task_from_json_string)
    |> result.map(fn(tasks) { #(offset, tasks) })
  })
}

/// Durable projection cursors are metadata beside, never inside, task state.
pub fn projection_checkpoint(
  workspace: String,
  projection: String,
) -> Result(Int, String) {
  ffi_projection_checkpoint(workspace, projection)
}

pub fn set_projection_checkpoint(
  workspace: String,
  projection: String,
  offset: Int,
) -> Result(Nil, String) {
  ffi_set_projection_checkpoint(workspace, projection, offset)
}

pub fn get_current(workspace: String, id: String) -> Result(Task, String) {
  ffi_get_current(workspace, id)
  |> result.try(serde.task_from_json_string)
}

/// Every task creation is a committed-change source event.
pub fn create(workspace: String, task: Task) -> Result(Task, String) {
  let hash = identity.hash_to_debug_string(task.content_hash)
  ffi_put_new(
    workspace,
    task.id,
    hash,
    serde.task_to_json_string(task),
    "create",
  )
  |> result.try(serde.task_from_json_string)
}

/// Atomically advances one stable task head and writes exactly one matching
/// committed change record. A stale head leaves neither mutation nor event.
pub fn replace(
  workspace: String,
  previous: Task,
  updated: Task,
) -> Result(Task, String) {
  ffi_compare_and_put(
    workspace,
    updated.id,
    identity.hash_to_debug_string(previous.content_hash),
    identity.hash_to_debug_string(updated.content_hash),
    serde.task_to_json_string(updated),
    "replace",
  )
  |> result.try(serde.task_from_json_string)
}

/// Apply a cluster-committed task transition exactly once. The command ID and
/// expected head are validated atomically with version/head/event persistence.
pub fn replace_committed(
  workspace: String,
  command_id: String,
  previous: Task,
  updated: Task,
) -> Result(Task, String) {
  ffi_compare_and_put_committed(
    workspace,
    command_id,
    updated.id,
    identity.hash_to_debug_string(previous.content_hash),
    identity.hash_to_debug_string(updated.content_hash),
    serde.task_to_json_string(updated),
    "cluster-committed",
  )
  |> result.try(serde.task_from_json_string)
}

/// Atomically advances a related set of task heads and emits one batch event.
/// The FFI validates every expected hash before writing any version/current
/// pair, so an incomplete duplicate merge cannot leak a half-rewritten graph.
pub fn replace_many(
  workspace: String,
  replacements: List(#(Task, Task)),
) -> Result(Nil, String) {
  replacements
  |> list.map(replacement_row)
  |> ffi_replace_many(workspace, _, "replace-many")
}

pub fn idempotent_result(
  workspace: String,
  idempotency_key: String,
  namespace: String,
) -> Result(Option(#(String, String)), String) {
  ffi_idempotent_result(workspace, idempotency_key, namespace)
}

pub fn replace_many_idempotent(
  workspace: String,
  idempotency_key: String,
  fingerprint: String,
  replacements: List(#(Task, Task)),
) -> Result(String, String) {
  replacements
  |> list.map(replacement_row)
  |> ffi_replace_many_idempotent(workspace, idempotency_key, fingerprint, _)
}

fn replacement_row(pair: #(Task, Task)) -> #(String, String, String, String) {
  let #(previous, updated) = pair
  #(
    updated.id,
    identity.hash_to_debug_string(previous.content_hash),
    identity.hash_to_debug_string(updated.content_hash),
    serde.task_to_json_string(updated),
  )
}
