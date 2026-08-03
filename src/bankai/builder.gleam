//// Ergonomic Task construction. Builds a draft then rehashes so the
//// content_hash is always correct. Reused by graph/actor/CLI layers.

import bankai/ast_bridge
import bankai/types.{type Relationship, type Task, type TaskStatus, Task}
import gleam/option.{type Option}
import gleam/string
import gleamunison/identity

pub fn build(
  id: String,
  title: String,
  description: String,
  status: TaskStatus,
  assignee: Option(String),
  priority: Int,
  created_at: Int,
  updated_at: Int,
  relationships: List(Relationship),
) -> Task {
  // G3: labels default to [] — existing callers are unchanged.
  let draft =
    Task(
      id: id,
      title: title,
      description: description,
      status: status,
      assignee: assignee,
      priority: priority,
      created_at: created_at,
      updated_at: updated_at,
      relationships: relationships,
      labels: [],
      content_hash: identity.hash_bytes(<<>>),
    )
  ast_bridge.rehash(draft)
}

/// Apply a field change and return a rehashed Task (hash advances). A `Task(..t,
/// ...)` spread carries `labels` through automatically.
pub fn update(task: Task, mutate: fn(Task) -> Task) -> Task {
  task
  |> mutate
  |> ast_bridge.rehash
}

/// Short, human-readable id derived from a content hash: "bk-" + first 4 hex
/// (G12). Replaces the timestamp ids (BUG-08: ms ids collided under rapid
/// creates; ns ids were 19 digits). A hash-prefix id is readable AND collision-
/// resistant — the draft includes a ns `created_at`, so identical content made
/// at different instants hashes to different ids. 4 hex matches the documented
/// `bk-a3f8` form.
pub fn short_id_from_hash(h: identity.Hash) -> String {
  "bk-" <> string.slice(identity.hash_to_debug_string(h), 0, 4)
}

/// Build a Task whose id is DERIVED from its own (placeholder) content hash,
/// not from the clock. The id is taken from a draft's hash (placeholder id
/// `"__pending__"`, REAL labels so the derived id is label-aware), then the
/// task is rebuilt with the real id + rehashed. No circularity: the id
/// references the placeholder-hash, not the final hash.
pub fn build_with_derived_id(
  title: String,
  description: String,
  status: TaskStatus,
  assignee: Option(String),
  priority: Int,
  created_at: Int,
  updated_at: Int,
  relationships: List(Relationship),
  labels: List(String),
) -> Task {
  let draft =
    Task(
      id: "__pending__",
      title: title,
      description: description,
      status: status,
      assignee: assignee,
      priority: priority,
      created_at: created_at,
      updated_at: updated_at,
      relationships: relationships,
      labels: labels,
      content_hash: identity.hash_bytes(<<>>),
    )
  let draft = ast_bridge.rehash(draft)
  let id = short_id_from_hash(draft.content_hash)
  let final =
    Task(
      id: id,
      title: title,
      description: description,
      status: status,
      assignee: assignee,
      priority: priority,
      created_at: created_at,
      updated_at: updated_at,
      relationships: relationships,
      labels: labels,
      content_hash: identity.hash_bytes(<<>>),
    )
  ast_bridge.rehash(final)
}
