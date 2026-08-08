//// Bankai's narrow Mnesia repository boundary. Records are canonical JSON so
//// Gleam's Task layout never leaks into the persisted Erlang schema.

import bankai/ast_bridge
import bankai/serde
import bankai/storage/store
import bankai/sync/merge
import bankai/types.{type Task, Wisp}
import gleam/list
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
) -> Result(String, String)

@external(erlang, "bankai_mnesia_ffi", "compare_and_put")
fn ffi_compare_and_put(
  workspace: String,
  id: String,
  expected_hash: String,
  hash: String,
  json: String,
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
) -> Result(Nil, String)

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

pub fn init(workspace: String) -> Result(Nil, String) {
  ffi_init(workspace)
}

/// Scoped test harness cleanup. Never used by application commands; it clears
/// only this workspace's Mnesia rows so repeatable tests do not leak history.
pub fn reset_workspace_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_workspace(workspace)
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

/// Derived aarondb indexes are rebuilt from this committed current-head view.
/// This narrow accessor is the change-feed seam: later cache/projection work can
/// attach invalidation here without making an index authoritative.
pub fn projection_source(workspace: String) -> Result(store.Store, String) {
  current_store(workspace)
}

pub fn get_current(workspace: String, id: String) -> Result(Task, String) {
  ffi_get_current(workspace, id)
  |> result.try(serde.task_from_json_string)
}

pub fn create(workspace: String, task: Task) -> Result(Task, String) {
  let hash = identity.hash_to_debug_string(task.content_hash)
  ffi_put_new(workspace, task.id, hash, serde.task_to_json_string(task))
  |> result.try(serde.task_from_json_string)
}

/// Atomically advances one stable task head. A stale head is rejected, so a
/// second concurrent claim/update cannot overwrite the first transaction.
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
  )
  |> result.try(serde.task_from_json_string)
}

/// Atomically advances a related set of task heads. The FFI validates every
/// expected hash before writing any version/current pair, so an incomplete
/// duplicate merge cannot leak a half-rewritten graph.
pub fn replace_many(
  workspace: String,
  replacements: List(#(Task, Task)),
) -> Result(Nil, String) {
  replacements
  |> list.map(fn(pair) {
    let #(previous, updated) = pair
    #(
      updated.id,
      identity.hash_to_debug_string(previous.content_hash),
      identity.hash_to_debug_string(updated.content_hash),
      serde.task_to_json_string(updated),
    )
  })
  |> ffi_replace_many(workspace, _)
}
