//// Ergonomic Task construction. Builds a draft then rehashes so the
//// content_hash is always correct. Reused by graph/actor/CLI layers.

import gleam/option.{type Option}
import gleamunison/identity
import bankai/ast_bridge
import bankai/types.{
  type Relationship, type Task, type TaskStatus, Task,
}

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
  let draft = Task(
    id: id,
    title: title,
    description: description,
    status: status,
    assignee: assignee,
    priority: priority,
    created_at: created_at,
    updated_at: updated_at,
    relationships: relationships,
    content_hash: identity.hash_bytes(<<>>),
  )
  ast_bridge.rehash(draft)
}

/// Apply a field change and return a rehashed Task (hash advances).
pub fn update(task: Task, mutate: fn(Task) -> Task) -> Task {
  task
  |> mutate
  |> ast_bridge.rehash
}
