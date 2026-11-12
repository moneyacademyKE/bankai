//// Conflict-record commands: list, resolve, clear, and merge recording.

import bankai/sync/conflicts
import bankai/sync/merge
import gleam/json
import gleam/list
import gleam/result

pub fn pending_conflict_tasks(workspace: String) -> List(String) {
  case conflicts.list_conflicts(workspace) {
    Ok(records) ->
      records
      |> list.filter_map(fn(r) {
        conflicts.parse_conflict_sides(r.detail)
        |> result.map(fn(sides) { sides.task })
      })
    Error(_) -> []
  }
}

/// Record new merge conflicts durably, skipping ids already pending.
/// Returns the ids recorded (fresh divergences only).
pub fn record_merge_conflicts(
  workspace: String,
  conflicts: List(merge.Conflict),
) -> List(String) {
  let pending = pending_conflict_tasks(workspace)
  conflicts
  |> list.filter(fn(c) { !list.contains(pending, c.id) })
  |> list.map(fn(c) {
    let detail = merge.conflict_detail(c)
    let _ = conflicts.record_conflict(workspace, "sync", detail)
    c.id
  })
}

pub fn sync_conflicts_cmd(workspace: String) -> Result(json.Json, String) {
  conflicts.list_conflicts(workspace)
  |> result.map(fn(conflicts) {
    json.array(conflicts, fn(c) {
      // A legacy or free-form detail is not a merge conflict, so it renders
      // without the parsed fields — the raw text stays visible either way.
      let parsed =
        conflicts.parse_conflict_sides(c.detail)
        |> result.map(fn(sides) {
          [
            #("task", json.string(sides.task)),
            #("local", json.string(sides.local)),
            #("remote", json.string(sides.remote)),
          ]
        })
        |> result.unwrap([])
      json.object([
        #("id", json.string(c.id)),
        #("timestamp", json.int(c.timestamp)),
        #("author", json.string(c.author)),
        #("detail", json.string(c.detail)),
        ..parsed
      ])
    })
  })
}

pub fn sync_resolve_cmd(
  workspace: String,
  conflict_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  use keep <- result.try(parse_keep(rest))
  use side <- result.try(conflicts.parse_side(keep))
  use record <- result.try(find_conflict(workspace, conflict_id))
  // Keep the conflict id for context, but surface the parse reason itself: it
  // carries the offending detail text, which is exactly what an operator needs
  // in order to resolve by hand. The old path erased it into Nil and then
  // replaced it with a generic sentence, hiding the one piece of evidence that
  // explains the refusal.
  use sides <- result.try(
    conflicts.parse_conflict_sides(record.detail)
    |> result.map_error(fn(reason) {
      "conflict " <> conflict_id <> " cannot be resolved: " <> reason
    }),
  )
  let chosen_hex = case side {
    conflicts.KeepLocal -> sides.local
    conflicts.KeepRemote -> sides.remote
  }
  // Resolution writes the chosen side as the authoritative head in Mnesia and
  // refreshes the JSONL export, so both views agree after the record is gone.
  use _ <- result.try(conflicts.resolve_conflict(workspace, conflict_id, side))
  Ok(
    json.object([
      #("resolved", json.string(conflict_id)),
      #("task", json.string(sides.task)),
      #("kept", json.string(keep)),
      #("chosen", json.string(chosen_hex)),
    ]),
  )
}

fn parse_keep(rest: List(String)) -> Result(String, String) {
  case rest {
    ["--keep", side, ..] if side == "local" || side == "remote" -> Ok(side)
    _ -> Error("usage: sync resolve <id> --keep local|remote")
  }
}

fn find_conflict(
  workspace: String,
  conflict_id: String,
) -> Result(conflicts.ConflictRecord, String) {
  conflicts.list_conflicts(workspace)
  |> result.try(fn(records) {
    records
    |> list.find(fn(r) { r.id == conflict_id })
    |> result.replace_error("unknown conflict: " <> conflict_id)
  })
}

pub fn sync_clear_cmd(workspace: String) -> Result(json.Json, String) {
  conflicts.clear_conflicts(workspace)
  |> result.map(fn(_) { json.string("cleared all replication conflicts") })
}
