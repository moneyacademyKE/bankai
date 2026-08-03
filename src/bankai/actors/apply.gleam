//// Pure task transitions. Each returns a rehashed Task (content_hash advances).

import bankai/builder
import bankai/types.{type Task, type TaskStatus, Blocks, Relationship, Task}

pub fn status(task: Task, new_status: TaskStatus, now: Int) -> Task {
  builder.update(task, fn(t) {
    Task(..t, status: new_status, updated_at: now)
  })
}

pub fn relation(task: Task, target_id: String, now: Int) -> Task {
  let rel = Relationship(target_id, Blocks)
  builder.update(task, fn(t) {
    Task(..t, relationships: [rel, ..t.relationships], updated_at: now)
  })
}
