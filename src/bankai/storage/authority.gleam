//// Authoritative replacement of a workspace's task state.
////
//// Import (a peer proposing a merge) and restore (a backup or a resolution
//// declaring the truth) are different operations: import preserves existing
//// heads and only advances causally behind ones, while these functions replace
//// the head set outright. Both write immutable versions and current heads in a
//// single transaction, so a failure leaves no half-applied authority.

import bankai/ast_bridge
import bankai/serde
import bankai/storage/store
import bankai/types.{type Task}
import gleam/list
import gleam/result
import gleamunison/identity

@external(erlang, "bankai_mnesia_ffi", "init")
fn ffi_init(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_mnesia_ffi", "restore_snapshot")
fn ffi_restore_snapshot(
  workspace: String,
  versions: List(#(String, String, String)),
  current: List(#(String, String, String)),
) -> Result(Nil, String)

pub fn validated_rows(
  index: store.Store,
) -> Result(
  #(List(#(String, String, String)), List(#(String, String, String))),
  String,
) {
  store.list(index)
  |> list.try_map(ast_bridge.validate)
  |> result.map(fn(_) { #(version_rows(index), current_rows(index)) })
}

pub fn version_rows(index: store.Store) -> List(#(String, String, String)) {
  store.list(index)
  |> list.map(row)
}

pub fn current_rows(index: store.Store) -> List(#(String, String, String)) {
  store.current_tasks(index)
  |> list.map(row)
}

pub fn row(task: Task) -> #(String, String, String) {
  #(
    task.id,
    identity.hash_to_debug_string(task.content_hash),
    serde.task_to_json_string(task),
  )
}

/// Authoritative restore: the supplied store becomes both the immutable version
/// history and the live head set, atomically. Used by backup restore, where the
/// backup is the declared truth rather than a peer proposing a merge.
pub fn restore_snapshot(
  workspace: String,
  incoming: store.Store,
) -> Result(Nil, String) {
  ffi_init(workspace)
  |> result.try(fn(_) {
    validated_rows(incoming)
    |> result.try(fn(rows) { ffi_restore_snapshot(workspace, rows.0, rows.1) })
  })
}

/// Write one newly created version and replace the active head set atomically.
/// Conflict resolution uses this: promotion creates a version (the chosen
/// content stamped as touched now), so the new row and the new heads must land
/// in one boundary.
pub fn promote_version(
  workspace: String,
  promoted: Task,
  heads: store.Store,
) -> Result(Nil, String) {
  use new_row <- result.try(ast_bridge.validate(promoted) |> result.map(row))
  heads
  |> store.list()
  |> list.try_map(ast_bridge.validate)
  |> result.try(fn(valid_heads) {
    ffi_restore_snapshot(workspace, [new_row], list.map(valid_heads, row))
  })
}
