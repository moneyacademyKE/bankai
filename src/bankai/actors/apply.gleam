//// Pure task transitions. Each returns a rehashed Task (content_hash advances).

import bankai/builder
import bankai/types.{type Task, type TaskStatus, Blocks, Relationship, Task}
import gleam/list

pub fn status(task: Task, new_status: TaskStatus, now: Int) -> Task {
  builder.update(task, fn(t) { Task(..t, status: new_status, updated_at: now) })
}

pub fn relation(task: Task, target_id: String, now: Int) -> Task {
  // BUG-04 fix: adding the same Blocks relation twice must be a TRUE no-op.
  // The old code prepended a duplicate every call, growing the list and churning
  // the content hash. An operation that changes nothing must not produce a new hash.
  let rel = Relationship(target_id, Blocks)
  builder.update(task, fn(t) {
    case list.contains(t.relationships, rel) {
      True -> t
      False ->
        Task(..t, relationships: [rel, ..t.relationships], updated_at: now)
    }
  })
}
