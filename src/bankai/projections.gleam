//// AaronDB 4.2 projection adapter for Bankai's committed Mnesia change source.
////
//// Mnesia remains the only task authority. This module owns no task state: it
//// adapts the committed snapshot/tail to AaronDB's durable-log, changefeed, and
//// projection contracts, making offset, lag, duplicate-delivery, and failure
//// state explicit for daemon diagnostics and query routing.

import aarondb/changefeed
import aarondb/durable_log
import aarondb/projection
import bankai/mnesia_store
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

@external(erlang, "bankai_projection_runtime_ffi", "start")
fn ffi_start_runtime(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_projection_runtime_ffi", "ensure")
fn ffi_ensure_runtime(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_projection_runtime_ffi", "reset_workspace")
fn ffi_reset_runtime(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_projection_runtime_ffi", "status")
fn ffi_runtime_status(
  workspace: String,
) -> Result(
  #(
    Bool,
    Int,
    String,
    Int,
    Int,
    String,
    String,
    Int,
    Int,
    String,
    String,
    Int,
    Int,
    String,
  ),
  String,
)

pub type RuntimeStatus {
  RuntimeStatus(
    healthy: Bool,
    high_watermark: Int,
    history_state: String,
    history_offset: Int,
    history_lag: Int,
    history_failure: String,
    text_state: String,
    text_offset: Int,
    text_lag: Int,
    text_failure: String,
    vector_state: String,
    vector_offset: Int,
    vector_lag: Int,
    vector_failure: String,
  )
}

/// Start the daemon-owned projection runtime. The FFI retains only a replayable
/// AaronDB view; Mnesia remains the source for every rebuild.
pub fn start_runtime(workspace: String) -> Result(Nil, String) {
  ffi_start_runtime(workspace)
}

/// Advance the existing runtime view from its durable Mnesia change cursor.
/// A daemon request sees a fully caught-up view or an explicit error, never an
/// in-between index.
pub fn ensure_runtime(workspace: String) -> Result(Nil, String) {
  ffi_ensure_runtime(workspace)
}

pub fn reset_runtime_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_runtime(workspace)
}

pub fn runtime_status(workspace: String) -> Result(RuntimeStatus, String) {
  ffi_runtime_status(workspace)
  |> result.map(fn(value) {
    let #(
      healthy,
      high_watermark,
      history_state,
      history_offset,
      history_lag,
      history_failure,
      text_state,
      text_offset,
      text_lag,
      text_failure,
      vector_state,
      vector_offset,
      vector_lag,
      vector_failure,
    ) = value
    RuntimeStatus(
      healthy,
      high_watermark,
      history_state,
      history_offset,
      history_lag,
      history_failure,
      text_state,
      text_offset,
      text_lag,
      text_failure,
      vector_state,
      vector_offset,
      vector_lag,
      vector_failure,
    )
  })
}

pub type View {
  View(
    source: durable_log.DurableLog,
    history: projection.Projection,
    text: projection.Projection,
    vector_membership: projection.Projection,
  )
}

pub type Health {
  Health(
    high_watermark: Int,
    history: projection.Status,
    text: projection.Status,
    vector_membership: projection.Status,
  )
}

pub fn empty(workspace: String) -> View {
  let source = durable_log.new(workspace)
  View(
    source,
    projection.new("bankai-history", 512, 3),
    projection.new("bankai-text", 512, 3),
    projection.new("bankai-vector-membership", 512, 3),
  )
}

/// Rebuild an AaronDB durable-log image from Bankai's Mnesia snapshot plus
/// ordered tail. Checkpoints that trail the journal (a crash between commit
/// and checkpoint) degrade to a full replay: projections are derived and
/// replay is idempotent, and the replay re-stamps checkpoints at the true
/// watermark.
pub fn bootstrap(workspace: String) -> Result(View, String) {
  mnesia_store.projection_snapshot(workspace)
  |> result.try(fn(snapshot) {
    snapshot_offset(snapshot)
    |> result.try(fn(offset) {
      mnesia_store.change_tail(workspace, -1)
      |> result.try(fn(entries) {
        let source = append_all(durable_log.new(workspace), "", entries)
        let view =
          View(
            source,
            projection.new("bankai-history", 512, 3),
            projection.new("bankai-text", 512, 3),
            projection.new("bankai-vector-membership", 512, 3),
          )
        case offset < 0 {
          True ->
            catch_up_all(view)
            |> result.try(fn(ready) { checkpoint_all(ready, workspace) })
          False ->
            case high_watermark(source) == offset {
              False ->
                catch_up_all(view)
                |> result.try(fn(ready) { checkpoint_all(ready, workspace) })
              True ->
                durable_log.snapshot(source, offset, snapshot)
                |> result.map_error(durable_error)
                |> result.try(fn(with_snapshot) {
                  catch_up_all(View(..view, source: with_snapshot))
                  |> result.try(fn(ready) { checkpoint_all(ready, workspace) })
                })
            }
        }
      })
    })
  })
}

/// Apply a tail after the last known offset. AaronDB projection semantics make
/// repeated entries a no-op, preserving at-least-once replay safety.
pub fn catch_up(view: View, workspace: String) -> Result(View, String) {
  let cursor = high_watermark(view.source)
  mnesia_store.change_tail(workspace, cursor)
  |> result.map(fn(entries) {
    let source = append_all(view.source, "", entries)
    View(..view, source:)
  })
  |> result.try(catch_up_all)
  |> result.try(fn(updated) { checkpoint_all(updated, workspace) })
}

pub fn health(view: View) -> Health {
  Health(
    high_watermark(view.source),
    projection.status(view.history, view.source),
    projection.status(view.text, view.source),
    projection.status(view.vector_membership, view.source),
  )
}

/// A derived read is healthy only when all three projections have caught up to
/// the committed source and carry no projection failure.
pub fn healthy(view: View) -> Bool {
  let Health(_, history, text, vector_membership) = health(view)
  status_is_fresh(history)
  && status_is_fresh(text)
  && status_is_fresh(vector_membership)
}

/// Demonstrates the bounded-credit, resumable AaronDB feed contract used by
/// daemon workers. `credits` must be positive; callers retain their own cursor.
pub fn pull(
  view: View,
  cursor: Int,
  credits: Int,
) -> Result(List(durable_log.Entry), String) {
  changefeed.resume(view.source, cursor, credits)
  |> result.map_error(changefeed_error)
  |> result.try(fn(feed) {
    changefeed.pull(feed)
    |> result.map_error(changefeed_error)
    |> result.map(fn(result) { result.1 })
  })
}

fn append_all(
  source: durable_log.DurableLog,
  snapshot: String,
  entries: List(String),
) -> durable_log.DurableLog {
  let seeded = case snapshot == "" {
    True -> source
    False -> {
      let #(next, _) = durable_log.append(source, snapshot, "snapshot")
      next
    }
  }
  list.fold(entries, seeded, fn(log, entry) {
    let #(next, _) = durable_log.append(log, entry, entry_id(entry))
    next
  })
}

fn catch_up_all(view: View) -> Result(View, String) {
  case projection.catch_up(view.history, view.source) {
    Error(error) -> Error(projection_error(error))
    Ok(#(history, source)) ->
      case projection.catch_up(view.text, source) {
        Error(error) -> Error(projection_error(error))
        Ok(#(text, source)) ->
          case projection.catch_up(view.vector_membership, source) {
            Error(error) -> Error(projection_error(error))
            Ok(#(vector_membership, source)) ->
              Ok(View(source, history, text, vector_membership))
          }
      }
  }
}

/// Cursor persistence happens only after every derived projection accepts the
/// same source watermark. A crash before this metadata write repeats delivery;
/// AaronDB projection offsets make that replay harmless.
fn checkpoint_all(view: View, workspace: String) -> Result(View, String) {
  let offset = high_watermark(view.source)
  mnesia_store.set_projection_checkpoint(workspace, "bankai-history", offset)
  |> result.try(fn(_) {
    mnesia_store.set_projection_checkpoint(workspace, "bankai-text", offset)
  })
  |> result.try(fn(_) {
    mnesia_store.set_projection_checkpoint(
      workspace,
      "bankai-vector-membership",
      offset,
    )
  })
  |> result.map(fn(_) { view })
}

fn high_watermark(source: durable_log.DurableLog) -> Int {
  source.next_offset - 1
}

fn status_is_fresh(status: projection.Status) -> Bool {
  let projection.Status(state, _offset, lag, failure, _generation, _metrics) =
    status
  case state, lag, failure {
    projection.Running, 0, option.None -> True
    _, _, _ -> False
  }
}

fn snapshot_offset(snapshot: String) -> Result(Int, String) {
  case string.split(snapshot, "\"offset\":") {
    [_, rest, ..] ->
      case string.split(rest, ",") {
        [offset, ..] ->
          int.parse(offset)
          |> result.map_error(fn(_) { "invalid snapshot offset" })
        _ -> Error("snapshot has no offset")
      }
    _ -> Error("snapshot has no offset")
  }
}

fn entry_id(entry: String) -> String {
  case string.split(entry, "\"event_id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [id, ..] -> id
        _ -> entry
      }
    _ -> entry
  }
}

fn durable_error(error: durable_log.DurableLogError) -> String {
  case error {
    durable_log.CursorExpired(_, _) -> "projection cursor expired"
    durable_log.CorruptEntry(_) -> "projection source is corrupt"
    durable_log.SnapshotUnavailable(_) -> "projection snapshot is unavailable"
    durable_log.CheckpointFaultInjected -> "projection checkpoint failed"
  }
}

fn changefeed_error(error: changefeed.ChangefeedError) -> String {
  case error {
    changefeed.InvalidCredit(_) -> "projection credits must be non-negative"
    changefeed.Source(source) -> durable_error(source)
  }
}

fn projection_error(error: projection.ProjectionError) -> String {
  case error {
    projection.BoundedPressure(_) ->
      "projection is lagging beyond its batch limit"
    projection.PermanentlyFailed(_) -> "projection has failed"
    projection.Source(source) -> durable_error(source)
    projection.Checkpoint(source) -> durable_error(source)
  }
}
