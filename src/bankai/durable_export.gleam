//// Serialized publication of the rebuildable Mnesia task-history export.
//// The captured watermark is a lower bound: mutations after it remain dirty,
//// even if the subsequent immutable-history snapshot happens to include them.

import bankai/mnesia_store
import bankai/storage/store
import bankai/sync/jsonl
import gleam/result

@external(erlang, "bankai_changefeed_ffi", "high_watermark")
fn ffi_high_watermark(workspace: String) -> Result(Int, String)

@external(erlang, "bankai_changefeed_ffi", "exported_offset")
fn ffi_exported_offset(workspace: String) -> Result(Int, String)

@external(erlang, "bankai_changefeed_ffi", "mark_exported_offset")
fn ffi_mark_exported_offset(
  workspace: String,
  offset: Int,
) -> Result(Nil, String)

@external(erlang, "bankai_export_ffi", "with_lock")
pub fn with_lock(
  path: String,
  action: fn() -> Result(a, String),
) -> Result(a, String)

/// Capture the watermark BEFORE the snapshot, under the same publication lock
/// used by explicit exports, conflict resolution, restore and compaction.
/// A custom destination never acknowledges the canonical tasks.jsonl file.
pub fn publish(
  workspace: String,
  path: String,
  snapshot: fn() -> Result(store.Store, String),
) -> Result(Nil, String) {
  use <- with_lock(workspace <> "/tasks.jsonl")
  use watermark <- result.try(ffi_high_watermark(workspace))
  use versions <- result.try(snapshot())
  use _ <- result.try(jsonl.flush_report(store.list(versions), to: path))
  case path == workspace <> "/tasks.jsonl" {
    True -> ffi_mark_exported_offset(workspace, watermark)
    False -> Ok(Nil)
  }
}

pub fn export_to(workspace: String, path: String) -> Result(Nil, String) {
  publish(workspace, path, fn() { mnesia_store.exportable_versions(workspace) })
}

pub fn refresh_if_stale(workspace: String) -> Result(Nil, String) {
  use <- with_lock(workspace <> "/tasks.jsonl")
  use exported <- result.try(ffi_exported_offset(workspace))
  use watermark <- result.try(ffi_high_watermark(workspace))
  case watermark > exported {
    False -> Ok(Nil)
    True -> export_to(workspace, workspace <> "/tasks.jsonl")
  }
}

/// Diagnostics: the export progress pair (exported, watermark).
pub fn progress(workspace: String) -> Result(#(Int, Int), String) {
  use exported <- result.try(ffi_exported_offset(workspace))
  use watermark <- result.try(ffi_high_watermark(workspace))
  Ok(#(exported, watermark))
}
