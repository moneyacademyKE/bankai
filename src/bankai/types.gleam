//// bankai core types. See docs/adrs/0001-hybrid-content-addressing.md.
////
//// NOTE: `content_hash` uses gleamunison/identity.Hash — the REAL opaque type.
//// It is NOT a String and NOT the fictional `ast.Hash` from the original spec
//// (Hash lives in gleamunison/identity, not gleamunison/ast).

import gleam/option.{type Option}
import gleamunison/identity.{type Hash}

pub type TaskKind {
  DefaultTask
  Bug
  Feature
  Epic
  Decision
  Chore
  Gate
  Wisp
}

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
  ParentChild
  WaitsFor
  DiscoveredFrom
  Tracks
  CausedBy
  Validates
  ConditionalBlocks
}

/// A single directed edge from the owning task to `target_id`.
pub type Relationship {
  Relationship(target_id: String, relation: RelationType)
}

/// A task in the dependency graph. `content_hash` is the SHA-256 of the task's
/// canonical byte encoding (which deliberately EXCLUDES content_hash itself — a
/// hash cannot include itself). Mutations recompute it; `id` stays stable.
///
/// `parent_id` is explicit parent linkage, separate from hierarchical display
/// IDs (bk-XXXX.N). Set via `create --parent <id>`. A ParentChild relation is
/// also created in `relationships`.
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
    parent_id: Option(String),
    kind: TaskKind,
    defer_until: Option(Int),
    closure_reason: Option(String),
    gate_due: Option(Int),
    gate_satisfied: Bool,
  )
}
