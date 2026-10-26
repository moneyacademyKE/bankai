//// Durable conflict records and operator-driven resolution.
////
//// A conflict is evidence, not a task state: it lives outside the head tables so
//// the divergence survives even when no materialization can advance. Resolution
//// requires an explicit side, and the record is deleted only after the chosen
//// version is the authoritative head — deleting first would destroy the only
//// proof of the fork.

import bankai/builder
import bankai/mnesia_store
import bankai/storage/authority
import bankai/storage/store
import bankai/sync/jsonl
import bankai/time
import bankai/types
import gleam/dict
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import gleam/string

@external(erlang, "bankai_replica_ffi", "record_conflict")
fn ffi_record_conflict(
  workspace: String,
  author: String,
  detail: String,
) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "list_conflicts")
fn ffi_list_conflicts(workspace: String) -> Result(String, String)

@external(erlang, "bankai_replica_ffi", "resolve_conflict")
fn ffi_resolve_conflict(
  workspace: String,
  conflict_id: String,
) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "clear_conflicts")
fn ffi_clear_conflicts(workspace: String) -> Result(Nil, String)

/// Domain conflicts are never silently imported. The conflict record is a
/// durable audit artifact outside the task-head tables, so causal evidence is
/// preserved even when the current materialization cannot advance.
pub fn record_conflict(
  workspace: String,
  author: String,
  detail: String,
) -> Result(Nil, String) {
  ffi_record_conflict(workspace, author, detail)
}

pub type ConflictRecord {
  ConflictRecord(id: String, timestamp: Int, author: String, detail: String)
}

fn conflict_record_decoder() -> decode.Decoder(ConflictRecord) {
  use id <- decode.field("id", decode.string)
  use timestamp <- decode.field("timestamp", decode.int)
  use author <- decode.field("author", decode.string)
  use detail <- decode.field("detail", decode.string)
  decode.success(ConflictRecord(id:, timestamp:, author:, detail:))
}

pub fn list_conflicts(
  workspace: String,
) -> Result(List(ConflictRecord), String) {
  use raw <- result.try(ffi_list_conflicts(workspace))
  json.parse(from: raw, using: decode.list(of: conflict_record_decoder()))
  |> result.map_error(fn(_) { "failed to decode conflict records" })
}

/// Which side of a recorded merge conflict becomes the authoritative head.
pub type Side {
  KeepLocal
  KeepRemote
}

pub fn parse_side(raw: String) -> Result(Side, String) {
  case raw {
    "local" -> Ok(KeepLocal)
    "remote" -> Ok(KeepRemote)
    _ -> Error("conflict side must be 'local' or 'remote', got: " <> raw)
  }
}

pub type ConflictSides {
  ConflictSides(task: String, local: String, remote: String)
}

/// The sync path records `task=<id> local=<hash> remote=<hash>`. Anything else
/// (legacy or free-form) is not a merge conflict and cannot be auto-resolved.
pub fn parse_conflict_sides(detail: String) -> Result(ConflictSides, String) {
  let fields =
    detail
    |> string.split(" ")
    |> list.filter_map(fn(token) {
      case string.split_once(token, on: "=") {
        Ok(#(key, value)) if value != "" -> Ok(#(key, value))
        _ -> Error(Nil)
      }
    })
    |> dict.from_list

  case
    dict.get(fields, "task"),
    dict.get(fields, "local"),
    dict.get(fields, "remote")
  {
    Ok(task), Ok(local), Ok(remote) -> Ok(ConflictSides(task:, local:, remote:))
    _, _, _ -> Error("conflict detail is not a merge conflict: " <> detail)
  }
}

/// Resolve a recorded merge conflict by promoting an explicitly chosen side to
/// the authoritative head, then delete the record. Deleting first would destroy
/// the only evidence of the divergence, so the record survives any failure here.
pub fn resolve_conflict(
  workspace: String,
  conflict_id: String,
  keep: Side,
) -> Result(Nil, String) {
  use record <- result.try(find_conflict_record(workspace, conflict_id))
  use sides <- result.try(parse_conflict_sides(record.detail))
  let chosen_hex = case keep {
    KeepLocal -> sides.local
    KeepRemote -> sides.remote
  }
  use versions <- result.try(authoritative_versions(workspace))
  use chosen <- result.try(
    store.get_by_hex(versions, chosen_hex)
    |> result.replace_error(
      "chosen version " <> chosen_hex <> " is not in this workspace's history",
    ),
  )
  case chosen.id == sides.task {
    False ->
      Error(
        "chosen version belongs to task "
        <> chosen.id
        <> ", not the conflicted task "
        <> sides.task,
      )
    True -> {
      // Promotion is a real content-addressed event: the chosen content is
      // stamped as touched now so it wins the head-by-recency view both
      // authorities derive. Both divergent versions stay in history and both
      // become parents of the promoted hash, so the fork is closed rather than
      // re-detected on the next pull.
      let promoted =
        builder.update(chosen, fn(task) {
          types.Task(..task, updated_at: time.now())
        })
      // The live head must still be one of the two sides the record names. If
      // the task moved on (or was deleted) since the fork was recorded, the
      // promotion is refused and the record survives for a fresh decision.
      use _ <- result.try(
        authority.promote_version(
          workspace,
          promoted,
          [sides.local, sides.remote],
          [sides.local, sides.remote],
        ),
      )
      use _ <- result.try(refresh_export(workspace))
      ffi_resolve_conflict(workspace, conflict_id)
    }
  }
}

/// Keep the JSONL export in step with the authoritative head set after a
/// resolution, so a reader of either view sees the same task state.
fn refresh_export(workspace: String) -> Result(Nil, String) {
  mnesia_store.version_store(workspace)
  |> result.try(fn(versions) {
    jsonl.flush(
      versions
        |> store.list
        |> list.filter(fn(task) { task.kind != types.Wisp }),
      to: workspace <> "/tasks.jsonl",
    )
    |> result.replace_error("could not refresh the task export")
  })
}

fn find_conflict_record(
  workspace: String,
  conflict_id: String,
) -> Result(ConflictRecord, String) {
  list_conflicts(workspace)
  |> result.try(fn(records) {
    records
    |> list.find(fn(record) { record.id == conflict_id })
    |> result.replace_error("unknown conflict: " <> conflict_id)
  })
}

/// Mnesia is the authority, but a workspace may still be JSONL-only (local CLI
/// use before the first daemon boot). Import that legacy history once so the
/// conflict's versions are addressable, then read from Mnesia alone.
fn authoritative_versions(workspace: String) -> Result(store.Store, String) {
  use versions <- result.try(mnesia_store.version_store(workspace))
  case store.size(versions) > 0 {
    True -> Ok(versions)
    False ->
      case jsonl.load(from: workspace <> "/tasks.jsonl") {
        Error(_) -> Ok(versions)
        Ok(tasks) -> {
          let legacy = store.from_list(tasks)
          use _ <- result.try(mnesia_store.import_legacy_if_needed(
            workspace,
            legacy,
          ))
          mnesia_store.version_store(workspace)
        }
      }
  }
}

pub fn clear_conflicts(workspace: String) -> Result(Nil, String) {
  ffi_clear_conflicts(workspace)
}
