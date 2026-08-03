//// Pure task transitions. Each returns a rehashed Task (content_hash advances).

import bankai/builder
import bankai/types.{
  type RelationType, type Task, type TaskStatus, Blocks, Relationship, Task,
}
import gleam/list

pub fn status(task: Task, new_status: TaskStatus, now: Int) -> Task {
  builder.update(task, fn(t) { Task(..t, status: new_status, updated_at: now) })
}

/// Add a Blocks relation (the common dependency case). Delegates to relation_typed.
pub fn relation(task: Task, target_id: String, now: Int) -> Task {
  relation_typed(task, target_id, Blocks, now)
}

/// Add a relation of any type (generalized for `dep add --type`). Idempotent
/// (BUG-04): adding an existing relation is a true no-op (hash unchanged).
pub fn relation_typed(
  task: Task,
  target_id: String,
  rel_type: RelationType,
  now: Int,
) -> Task {
  let rel = Relationship(target_id, rel_type)
  builder.update(task, fn(t) {
    case list.contains(t.relationships, rel) {
      True -> t
      False ->
        Task(..t, relationships: [rel, ..t.relationships], updated_at: now)
    }
  })
}
