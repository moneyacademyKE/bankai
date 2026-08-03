//// Phase 4 (G5 + G6) tests: compaction (tier+retire) + git-transport sync.

import bankai/cli
import bankai/serde
import bankai/types
import gleam/dynamic/decode
import gleam/json
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
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = simplifile.write("", to: ws <> "/archive.jsonl")
  Nil
}

fn ok_task_decoder() -> decode.Decoder(types.Task) {
  use task <- decode.field("ok", serde.task_decoder())
  decode.success(task)
}

fn task_from_output(output: String) -> Result(types.Task, json.DecodeError) {
  json.parse(from: output, using: ok_task_decoder())
}

// G5 ----------------------------------------------------------

pub fn compact_archives_closed_keeps_open_test() {
  let ws = "/tmp/bankai_compact_archive"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _open =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Open one"])))
  let closed =
    should.be_ok(task_from_output(cli.run_in(ws, ["create", "Closed one"])))
  let _ = cli.run_in(ws, ["update", closed.id, "closed"])

  cli.run_in(ws, ["compact"])
  |> string.contains("Compacted 1 closed task")
  |> should.be_true

  // closed task left the active set
  cli.run_in(ws, ["list"])
  |> string.contains("Closed one")
  |> should.be_false
  // open task remains
  cli.run_in(ws, ["list"])
  |> string.contains("Open one")
  |> should.be_true
}

pub fn compact_records_a_summary_memory_test() {
  let ws = "/tmp/bankai_compact_mem"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let t = should.be_ok(task_from_output(cli.run_in(ws, ["create", "To close"])))
  let _ = cli.run_in(ws, ["update", t.id, "closed"])
  let _ = cli.run_in(ws, ["compact"])
  cli.run_in(ws, ["memories"])
  |> string.contains("Compacted")
  |> should.be_true
}

pub fn compact_with_nothing_closed_is_a_noop_test() {
  let ws = "/tmp/bankai_compact_noop"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Still open"])
  cli.run_in(ws, ["compact"])
  |> string.contains("nothing to compact")
  |> should.be_true
}

// G6 ----------------------------------------------------------

pub fn sync_from_unions_remote_tasks_test() {
  let ws = "/tmp/bankai_sync_local"
  let remote = "/tmp/bankai_sync_remote"
  wipe(ws)
  wipe(remote)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(remote, ["init"])
  let _ = cli.run_in(ws, ["create", "Local A"])
  let _ = cli.run_in(remote, ["create", "Remote B"])

  // union-merge the remote tasks.jsonl into local (the transport — git
  // pull/rsync — is the agent's job; bankai is the merge).
  cli.run_in(ws, ["sync", "--from", remote <> "/tasks.jsonl"])
  |> string.contains("merged")
  |> should.be_true

  // local now has both (content-addressed union)
  let list_out = cli.run_in(ws, ["list"])
  list_out |> string.contains("Local A") |> should.be_true
  list_out |> string.contains("Remote B") |> should.be_true
}

pub fn sync_without_from_reconciles_local_test() {
  let ws = "/tmp/bankai_sync_reconcile"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Solo"])
  cli.run_in(ws, ["sync"])
  |> string.contains("synced")
  |> should.be_true
}
