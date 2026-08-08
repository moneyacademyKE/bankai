//// Task <-> JSON serialization for the JSONL persistence + sync layer.
////
//// Encode with gleam/json; decode with gleam/dynamic/decode combinators run
//// against the Dynamic from json.parse. content_hash round-trips as hex.
////
//// Legacy records (v2 canonical) lack `kind` and `parent_id`. Decoding falls
//// back to `Task` kind and `None` parent respectively — no destructive migration.

import bankai/ast_bridge
import bankai/types.{
  type RelationType, type Relationship, type Task, type TaskKind,
  type TaskStatus, Blocked, Blocks, Bug, CausedBy, Chore, Closed, Completed,
  ConditionalBlocks, Decision, DefaultTask, DiscoveredFrom, Duplicates, Epic,
  Feature, Gate, InProgress, Open, ParentChild, RelatesTo, Relationship,
  RepliesTo, Supersedes, Task, Tracks, Validates, WaitsFor, Wisp,
}
import gleam/dynamic/decode
import gleam/json
import gleam/option
import gleamunison/identity

// --- encode ---

pub fn task_to_json(task: Task) -> json.Json {
  json.object([
    #("id", json.string(task.id)),
    #("title", json.string(task.title)),
    #("description", json.string(task.description)),
    #("status", json.string(status_to_string(task.status))),
    #("assignee", json.nullable(task.assignee, of: json.string)),
    #("priority", json.int(task.priority)),
    #("created_at", json.int(task.created_at)),
    #("updated_at", json.int(task.updated_at)),
    #(
      "relationships",
      json.array(task.relationships, of: fn(r) {
        json.object([
          #("target_id", json.string(r.target_id)),
          #("relation", json.string(relation_to_string(r.relation))),
        ])
      }),
    ),
    #("labels", json.array(task.labels, of: json.string)),
    #(
      "content_hash",
      json.string(identity.hash_to_debug_string(task.content_hash)),
    ),
    #("kind", json.string(kind_to_string(task.kind))),
    #("parent_id", json.nullable(task.parent_id, of: json.string)),
    #("defer_until", json.nullable(task.defer_until, of: json.int)),
    #("closure_reason", json.nullable(task.closure_reason, of: json.string)),
    #("gate_due", json.nullable(task.gate_due, of: json.int)),
    #("gate_satisfied", json.bool(task.gate_satisfied)),
  ])
}

pub fn task_to_json_string(task: Task) -> String {
  json.to_string(task_to_json(task))
}

pub fn task_from_json_string(s: String) -> Result(Task, String) {
  case json.parse(from: s, using: task_decoder()) {
    Ok(t) -> Ok(t)
    Error(_) -> Error("task decode failed")
  }
}

pub fn task_decoder() -> decode.Decoder(Task) {
  use id <- decode.field("id", decode.string)
  use title <- decode.field("title", decode.string)
  use description <- decode.field("description", decode.string)
  use status_str <- decode.field("status", decode.string)
  use assignee <- decode.field("assignee", decode.optional(decode.string))
  use priority <- decode.field("priority", decode.int)
  use created_at <- decode.field("created_at", decode.int)
  use updated_at <- decode.field("updated_at", decode.int)
  use relationships <- decode.field(
    "relationships",
    decode.list(of: relationship_decoder()),
  )
  use labels <- decode.field("labels", decode.list(of: decode.string))
  use hash_hex <- decode.field("content_hash", decode.string)
  use kind_str <- decode.optional_field("kind", "task", decode.string)
  use parent_id <- decode.optional_field(
    "parent_id",
    option.None,
    decode.optional(decode.string),
  )
  use defer_until <- decode.optional_field(
    "defer_until",
    option.None,
    decode.optional(decode.int),
  )
  use closure_reason <- decode.optional_field(
    "closure_reason",
    option.None,
    decode.optional(decode.string),
  )
  use gate_due <- decode.optional_field(
    "gate_due",
    option.None,
    decode.optional(decode.int),
  )
  use gate_satisfied <- decode.optional_field(
    "gate_satisfied",
    False,
    decode.bool,
  )
  let kind = kind_from_string(kind_str)
  case status_from_string(status_str) {
    Ok(status) -> {
      let task =
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
          content_hash: identity.hash_from_bytes(identity.hex_to_bytes(hash_hex)),
          parent_id: parent_id,
          kind: kind,
          defer_until: defer_until,
          closure_reason: closure_reason,
          gate_due: gate_due,
          gate_satisfied: gate_satisfied,
        )
      case ast_bridge.validate(task) {
        Ok(valid) -> decode.success(valid)
        Error(_) -> decode.failure(task, "matching canonical content_hash")
      }
    }
    Error(Nil) ->
      decode.failure(
        Task(
          id,
          title,
          description,
          Open,
          assignee,
          priority,
          created_at,
          updated_at,
          relationships,
          labels,
          identity.hash_from_bytes(identity.hex_to_bytes(hash_hex)),
          parent_id: parent_id,
          kind: kind,
          defer_until: defer_until,
          closure_reason: closure_reason,
          gate_due: gate_due,
          gate_satisfied: gate_satisfied,
        ),
        "valid status",
      )
  }
}

fn relationship_decoder() -> decode.Decoder(Relationship) {
  use target_id <- decode.field("target_id", decode.string)
  use relation_str <- decode.field("relation", decode.string)
  case relation_from_string(relation_str) {
    Ok(relation) -> decode.success(Relationship(target_id, relation))
    Error(Nil) ->
      decode.failure(Relationship(target_id, Blocks), "valid relation")
  }
}

// --- enum string mappings ---

pub fn status_to_string(s: TaskStatus) -> String {
  case s {
    Open -> "open"
    InProgress -> "in_progress"
    Blocked -> "blocked"
    Completed -> "completed"
    Closed -> "closed"
  }
}

pub fn status_from_string(s: String) -> Result(TaskStatus, Nil) {
  case s {
    "open" -> Ok(Open)
    "in_progress" -> Ok(InProgress)
    "blocked" -> Ok(Blocked)
    "completed" -> Ok(Completed)
    "closed" -> Ok(Closed)
    _ -> Error(Nil)
  }
}

pub fn kind_to_string(k: TaskKind) -> String {
  case k {
    DefaultTask -> "task"
    Bug -> "bug"
    Feature -> "feature"
    Epic -> "epic"
    Decision -> "decision"
    Chore -> "chore"
    Gate -> "gate"
    Wisp -> "wisp"
  }
}

pub fn kind_from_string(s: String) -> TaskKind {
  case s {
    "bug" -> Bug
    "feature" -> Feature
    "epic" -> Epic
    "decision" -> Decision
    "chore" -> Chore
    "gate" -> Gate
    "wisp" -> Wisp
    _ -> DefaultTask
  }
}

fn relation_to_string(r: RelationType) -> String {
  case r {
    Blocks -> "blocks"
    RelatesTo -> "relates_to"
    Duplicates -> "duplicates"
    Supersedes -> "supersedes"
    RepliesTo -> "replies_to"
    ParentChild -> "parent_child"
    WaitsFor -> "waits_for"
    DiscoveredFrom -> "discovered_from"
    Tracks -> "tracks"
    CausedBy -> "caused_by"
    Validates -> "validates"
    ConditionalBlocks -> "conditional_blocks"
  }
}

pub fn relation_from_string(s: String) -> Result(RelationType, Nil) {
  case s {
    "blocks" -> Ok(Blocks)
    "relates_to" | "relates-to" -> Ok(RelatesTo)
    "duplicates" -> Ok(Duplicates)
    "supersedes" -> Ok(Supersedes)
    "replies_to" | "replies-to" -> Ok(RepliesTo)
    "parent_child" | "parent-child" -> Ok(ParentChild)
    "waits_for" | "waits-for" -> Ok(WaitsFor)
    "discovered_from" | "discovered-from" -> Ok(DiscoveredFrom)
    "tracks" -> Ok(Tracks)
    "caused_by" | "caused-by" -> Ok(CausedBy)
    "validates" -> Ok(Validates)
    "conditional_blocks" | "conditional-blocks" -> Ok(ConditionalBlocks)
    _ -> Error(Nil)
  }
}
