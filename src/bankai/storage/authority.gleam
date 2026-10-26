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

@external(erlang, "bankai_mnesia_ffi", "promote_row")
fn ffi_promote_row(
  workspace: String,
  id: String,
  hash: String,
  json: String,
  parents: List(String),
  expected: String,
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

/// Write one newly created version, link it to the versions it was chosen from,
/// and make it the head of exactly that task — atomically.
///
/// Conflict resolution uses this. The ancestry links are the load-bearing part:
/// a promoted hash is otherwise a node with no edges, so a peer still holding
/// either side of the fork sees a fresh divergence instead of a descendant and
/// refuses to sync again. Linking the promoted version to both sides makes the
/// resolution converge.
///
/// `parents` are the version hashes this promotion was chosen from (the fork's
/// two sides). The promoted hash itself is never its own parent.
///
/// `expected` is the head the conflict was recorded against. If the task moved
/// or disappeared since then the promotion is refused rather than applied on
/// stale evidence — a resolution must never overwrite newer work or bring a
/// deleted task back.
pub fn promote_version(
  workspace: String,
  promoted: Task,
  parents: List(String),
  expected: String,
) -> Result(Nil, String) {
  use new_row <- result.try(ast_bridge.validate(promoted) |> result.map(row))
  ffi_promote_row(workspace, new_row.0, new_row.1, new_row.2, parents, expected)
}
