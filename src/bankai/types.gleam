//// bankai core types. See docs/adrs/0001-hybrid-content-addressing.md.
////
//// NOTE: `content_hash` uses gleamunison/identity.Hash — the REAL opaque type.
//// It is NOT a String and NOT the fictional `ast.Hash` from the original spec
//// (Hash lives in gleamunison/identity, not gleamunison/ast).

import gleam/option.{type Option}
import gleamunison/identity.{type Hash}

pub type TaskStatus {
  Open
  InProgress
  Blocked
  Completed
  Closed
}

pub type RelationType {
  Blocks
  RelatesTo
  Duplicates
  Supersedes
  RepliesTo
}

/// A single directed edge from the owning task to `target_id`.
pub type Relationship {
  Relationship(target_id: String, relation: RelationType)
}

/// A task in the dependency graph. `content_hash` is the SHA-256 of the task's
/// canonical byte encoding (which deliberately EXCLUDES content_hash itself — a
/// hash cannot include itself). Mutations recompute it; `id` stays stable.
pub type Task {
  Task(
    id: String,
    title: String,
    description: String,
    status: TaskStatus,
    assignee: Option(String),
    priority: Int,
    created_at: Int,
    updated_at: Int,
    relationships: List(Relationship),
    labels: List(String),
    content_hash: Hash,
  )
}
