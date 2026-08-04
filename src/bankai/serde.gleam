//// Task <-> JSON serialization for the JSONL persistence + sync layer.
////
//// Encode with gleam/json; decode with gleam/dynamic/decode combinators run
//// against the Dynamic from json.parse. content_hash round-trips as hex.

import bankai/types.{
  type RelationType, type Relationship, type Task, type TaskStatus, Blocked,
  Blocks, Closed, Completed, Duplicates, InProgress, Open, RelatesTo,
  Relationship, RepliesTo, Supersedes, Task,
}
import gleam/dynamic/decode
import gleam/json
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
  ])
}

pub fn task_to_json_string(task: Task) -> String {
  json.to_string(task_to_json(task))
}

// --- decode ---

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
  case status_from_string(status_str) {
    Ok(status) ->
      decode.success(Task(
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
      ))
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

fn relation_to_string(r: RelationType) -> String {
  case r {
    Blocks -> "blocks"
    RelatesTo -> "relates_to"
    Duplicates -> "duplicates"
    Supersedes -> "supersedes"
    RepliesTo -> "replies_to"
  }
}

pub fn relation_from_string(s: String) -> Result(RelationType, Nil) {
  case s {
    "blocks" -> Ok(Blocks)
    "relates_to" | "relates-to" -> Ok(RelatesTo)
    "duplicates" -> Ok(Duplicates)
    "supersedes" -> Ok(Supersedes)
    "replies_to" | "replies-to" -> Ok(RepliesTo)
    _ -> Error(Nil)
  }
}
