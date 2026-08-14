//// Federation conflict UX: the local-file sync merge path must record
//// same-id-different-hash divergences durably (they were previously counted
//// and dropped), the listing must expose structured task/local/remote fields,
//// and re-syncing the same unresolved remote must not duplicate the record.

import bankai/builder
import bankai/cli
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync_peer
import bankai/types.{type Task, Open}
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  // Cross-run isolation: pending conflict records from a previous test run
  // must not leak into this one.
  let _ = simplifile.delete(ws <> "/identity/conflicts.term")
  Nil
}

fn task_v1() -> Task {
  builder.build(
    "bk-0001",
    "Original title",
    "d",
    Open,
    option.None,
    1,
    1000,
    1000,
    [],
  )
}

fn task_v2() -> Task {
  builder.build(
    "bk-0001",
    "Divergent title",
    "d",
    Open,
    option.None,
    1,
    2000,
    2000,
    [],
  )
}

fn setup_conflict(ws: String, remote_path: String) -> String {
  wipe(ws)
  let _ = jsonl.flush([task_v1()], to: ws <> "/tasks.jsonl")
  let _ = jsonl.flush([task_v2()], to: remote_path)
  cli.run_in(ws, ["sync", "--from", remote_path])
}

/// Syncing a divergent remote records exactly one structured conflict.
pub fn conflicting_sync_records_structured_conflict_test() {
  let ws = "/tmp/bankai_conflict_ux_ws"
  let remote = "/tmp/bankai_conflict_ux_remote.jsonl"
  let _ = setup_conflict(ws, remote)

  let conflicts = should.be_ok(sync_peer.list_conflicts(ws))
  should.equal(list.length(conflicts), 1)

  let assert Ok(record) = list.first(conflicts)
  record.detail |> string.contains("task=bk-0001") |> should.be_true
  record.detail
  |> string.contains("local=" <> store.hash_key(task_v1().content_hash))
  |> should.be_true
  record.detail
  |> string.contains("remote=" <> store.hash_key(task_v2().content_hash))
  |> should.be_true
}

/// The sync report names the conflicted ids instead of just a count.
pub fn conflicting_sync_report_names_ids_test() {
  let ws = "/tmp/bankai_conflict_ux_report_ws"
  let remote = "/tmp/bankai_conflict_ux_report_remote.jsonl"
  let out = setup_conflict(ws, remote)
  out |> string.contains("bk-0001") |> should.be_true
  out |> string.contains("conflict") |> should.be_true
}

/// Re-syncing the same unresolved remote does not duplicate the record.
pub fn resync_does_not_duplicate_pending_conflict_test() {
  let ws = "/tmp/bankai_conflict_ux_resync_ws"
  let remote = "/tmp/bankai_conflict_ux_resync_remote.jsonl"
  let _ = setup_conflict(ws, remote)
  let _ = cli.run_in(ws, ["sync", "--from", remote])
  let _ = cli.run_in(ws, ["sync", "--from", remote])

  let conflicts = should.be_ok(sync_peer.list_conflicts(ws))
  should.equal(list.length(conflicts), 1)
}

/// A clean merge (identical hashes) records nothing.
pub fn clean_sync_records_nothing_test() {
  let ws = "/tmp/bankai_conflict_ux_clean_ws"
  let remote = "/tmp/bankai_conflict_ux_clean_remote.jsonl"
  wipe(ws)
  let _ = jsonl.flush([task_v1()], to: ws <> "/tasks.jsonl")
  let _ = jsonl.flush([task_v1()], to: remote)
  let _ = cli.run_in(ws, ["sync", "--from", remote])

  let conflicts = should.be_ok(sync_peer.list_conflicts(ws))
  should.equal(list.length(conflicts), 0)
}

/// The listing exposes machine-usable task/local/remote fields.
pub fn conflicts_listing_parses_structured_detail_test() {
  let ws = "/tmp/bankai_conflict_ux_list_ws"
  let remote = "/tmp/bankai_conflict_ux_list_remote.jsonl"
  let _ = setup_conflict(ws, remote)

  let out = cli.run_in(ws, ["sync", "conflicts"])
  // Envelope is {"ok": [...]} — find parsed fields in the payload.
  out |> string.contains("\"task\":\"bk-0001\"") |> should.be_true
  out |> string.contains("\"local\"") |> should.be_true
  out |> string.contains("\"remote\"") |> should.be_true
}

/// Legacy free-text details still render (raw detail, no parsed fields).
pub fn conflicts_listing_renders_legacy_detail_test() {
  let ws = "/tmp/bankai_conflict_ux_legacy_ws"
  wipe(ws)
  let _ =
    sync_peer.record_conflict(ws, "upstream-rig", "snapshot gap at clock 42")

  let out = cli.run_in(ws, ["sync", "conflicts"])
  out |> string.contains("snapshot gap at clock 42") |> should.be_true
  out |> string.contains("\"task\"") |> should.be_false
}

/// Divergence is verifiable end to end: both versions survive in history.
pub fn conflicting_sync_retains_both_versions_test() {
  let ws = "/tmp/bankai_conflict_ux_versions_ws"
  let remote = "/tmp/bankai_conflict_ux_versions_remote.jsonl"
  let _ = setup_conflict(ws, remote)

  let raw = should.be_ok(simplifile.read(ws <> "/tasks.jsonl"))
  let titles =
    raw
    |> string.split("\n")
    |> list.filter_map(fn(line) {
      case line {
        "" -> Error(Nil)
        _ ->
          serde.task_from_json_string(line)
          |> result_map_title
      }
    })
  titles |> list.contains("Original title") |> should.be_true
  titles |> list.contains("Divergent title") |> should.be_true
}

fn result_map_title(r: Result(Task, String)) -> Result(String, Nil) {
  case r {
    Ok(t) -> Ok(t.title)
    Error(_) -> Error(Nil)
  }
}
