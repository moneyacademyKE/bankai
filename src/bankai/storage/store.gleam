//// The content-addressed store: a Hash -> Task index.
////
//// Per ADR-0001 amendment, this is bankai's own dict-backed store (not aarondb).
//// Every Task version is stored under its own content_hash, so the full history
//// graph is addressable. Persistence to .bankai/tasks.jsonl lives in Phase 6
//// (bankai/sync); this module is the in-memory index + a to_list/from_list seam.

import gleam/dict.{type Dict}
import gleam/list
import gleam/string
import gleamunison/identity.{type Hash, hash_to_debug_string}
import bankai/types.{type Task}

pub opaque type Store {
  Store(tasks: Dict(String, Task))
}

pub fn new() -> Store {
  Store(tasks: dict.new())
}

/// Hex string of a Hash — the stable store key (Hash is opaque).
pub fn hash_key(h: Hash) -> String {
  hash_to_debug_string(h)
}

/// Store a task version under its content_hash.
pub fn put(store: Store, task: Task) -> Store {
  Store(tasks: dict.insert(store.tasks, hash_key(task.content_hash), task))
}

/// Fetch a task version by its content hash.
pub fn get(store: Store, hash: Hash) -> Result(Task, Nil) {
  dict.get(store.tasks, hash_key(hash))
}

/// Fetch by hex key (used by CLI `inspect <hash>` and JSONL reload).
pub fn get_by_hex(store: Store, hex: String) -> Result(Task, Nil) {
  dict.get(store.tasks, hex)
}

/// Find the current (latest) task version for an id — O(n) scan.
pub fn find_by_id(store: Store, id: String) -> Result(Task, Nil) {
  store
  |> current_tasks()
  |> list.find(fn(t) { t.id == id })
}

/// The current task per id (latest version by updated_at). The content-addressed
/// store retains ALL versions (the history); this is the "HEAD" view over it —
/// what list/ready/find_by_id operate on.
pub fn current_tasks(store: Store) -> List(Task) {
  store.tasks
  |> dict.values()
  |> list.fold(dict.new(), group_latest)
  |> dict.values()
  |> list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
}

fn group_latest(acc: Dict(String, Task), t: Task) -> Dict(String, Task) {
  case dict.get(acc, t.id) {
    Ok(existing) ->
      case t.updated_at >= existing.updated_at {
        True -> dict.insert(acc, t.id, t)
        False -> acc
      }
    Error(Nil) -> dict.insert(acc, t.id, t)
  }
}

/// All stored versions, ordered by hash key for stable output.
pub fn list(store: Store) -> List(Task) {
  store.tasks
  |> dict.values()
  |> list.sort(by: fn(a, b) {
    string.compare(hash_key(a.content_hash), hash_key(b.content_hash))
  })
}

pub fn size(store: Store) -> Int {
  dict.size(store.tasks)
}

/// Persistence seam for Phase 6 (JSONL reload/flush).
pub fn to_list(store: Store) -> List(Task) {
  list(store)
}

pub fn from_list(tasks: List(Task)) -> Store {
  list.fold(tasks, new(), fn(store, t) { put(store, t) })
}
