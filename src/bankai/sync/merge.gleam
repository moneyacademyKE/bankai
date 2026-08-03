//// Content-addressed 3-way merge across rigs.
////
//// Because every task version is content-addressed (its SHA-256), two sides
//// that agree produce identical hashes and union cleanly. A real conflict is
//// ONLY when the same task id has diverged to different hashes — those are
//// surfaced (never silently overwritten) and routed to conflicts.jsonl.

import bankai/storage/store
import bankai/types.{type Task}
import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import gleamunison/identity

pub type Conflict {
  Conflict(id: String, local_hash: String, remote_hash: String)
}

pub type MergeResult {
  MergeResult(tasks: List(Task), conflicts: List(Conflict))
}

/// Merge two task sets. Distinct hashes union; same-id-different-hash -> conflict.
pub fn merge(local: List(Task), remote: List(Task)) -> MergeResult {
  let merged = dedupe_by_hash(list.append(local, remote))
  let conflicts = id_conflicts(index_by_id(local), index_by_id(remote))
  MergeResult(merged, conflicts)
}

/// True when both sides have the same set of hashes (no divergence at all).
pub fn clean_merge(local: List(Task), remote: List(Task)) -> Bool {
  let conflicts = id_conflicts(index_by_id(local), index_by_id(remote))
  list.is_empty(conflicts)
}

// --- internals ---

fn dedupe_by_hash(tasks: List(Task)) -> List(Task) {
  tasks
  |> list.fold(dict.new(), fn(acc, t) {
    dict.insert(acc, store.hash_key(t.content_hash), t)
  })
  |> dict.values()
  |> list.sort(by: fn(a, b) {
    string.compare(
      store.hash_key(a.content_hash),
      store.hash_key(b.content_hash),
    )
  })
}

fn index_by_id(tasks: List(Task)) -> Dict(String, Task) {
  list.fold(tasks, dict.new(), fn(acc, t) { dict.insert(acc, t.id, t) })
}

fn id_conflicts(
  local: Dict(String, Task),
  remote: Dict(String, Task),
) -> List(Conflict) {
  local
  |> dict.to_list()
  |> list.filter_map(fn(pair) {
    let #(id, l) = pair
    case dict.get(remote, id) {
      Ok(r) ->
        case identity.hash_equal(l.content_hash, r.content_hash) {
          True -> Error(Nil)
          False ->
            Ok(Conflict(
              id: id,
              local_hash: store.hash_key(l.content_hash),
              remote_hash: store.hash_key(r.content_hash),
            ))
        }
      Error(Nil) -> Error(Nil)
    }
  })
}
