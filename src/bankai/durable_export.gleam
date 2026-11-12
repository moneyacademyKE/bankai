//// The durable-export pulse: keep tasks.jsonl within one request of the
//// authoritative Mnesia store.
////
//// The freshness signal is the changefeed watermark, not a method
//// classification list: every task mutation records a change inside its
//// Mnesia transaction (the projection runtime already depends on that), so
//// keying the export to the feed inherits that integrity — a new mutation
//// route can never be forgotten here.

import bankai/daemon_store
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

/// Export the immutable task history when the changefeed has advanced past
/// the last export. The watermark is read again AFTER the export, and the
/// marker takes that later value: a change landing mid-export leaves the
/// marker one behind, so the next request re-exports rather than lagging.
pub fn refresh_if_stale(workspace: String) -> Result(Nil, String) {
  use exported <- result.try(ffi_exported_offset(workspace))
  use watermark <- result.try(ffi_high_watermark(workspace))
  case watermark > exported {
    False -> Ok(Nil)
    True ->
      daemon_store.export_jsonl(workspace)
      |> result.try(fn(_exported) { ffi_high_watermark(workspace) })
      |> result.try(fn(caught_up) {
        ffi_mark_exported_offset(workspace, caught_up)
      })
  }
}

/// Diagnostics: the export progress pair (exported, watermark).
pub fn progress(workspace: String) -> Result(#(Int, Int), String) {
  use exported <- result.try(ffi_exported_offset(workspace))
  use watermark <- result.try(ffi_high_watermark(workspace))
  Ok(#(exported, watermark))
}
