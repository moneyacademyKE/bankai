import bankai/cli
import bankai/sync_peer
import gleam/erlang/process
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  Nil
}

/// G6 livesync: a running rig (sync-serve) streams its task set; a peer
/// (sync-pull) connects over TCP and union-merges. Convergence is free via
/// content-addressing — both rigs end up with the union.
pub fn pull_merges_remote_tasks_into_local_test() {
  let local = "/tmp/bankai_livesync_local"
  let remote = "/tmp/bankai_livesync_remote"
  wipe(local)
  wipe(remote)
  let _ = cli.run_in(local, ["init"])
  let _ = cli.run_in(remote, ["init"])
  let _ = cli.run_in(local, ["create", "Local only"])
  let _ = cli.run_in(remote, ["create", "Remote only"])

  // Run the remote's sync-serve in a spawned (unlinked) process so it doesn't
  // take the test down and dies with the VM.
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_661) })
  process.sleep(200)

  let out =
    cli.run_in(local, ["sync-pull", "--host", "localhost", "--port", "17661"])
  out |> string.contains("pulled") |> should.be_true

  // local converged: it now holds both rigs' tasks.
  let list_out = cli.run_in(local, ["list"])
  list_out |> string.contains("Local only") |> should.be_true
  list_out |> string.contains("Remote only") |> should.be_true
}

/// sync-pull to a port with no listener is a clean error envelope, not a crash.
pub fn pull_with_no_peer_is_an_error_test() {
  let ws = "/tmp/bankai_livesync_nopeer"
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  cli.run_in(ws, ["sync-pull", "--host", "localhost", "--port", "17699"])
  |> string.contains("could not connect")
  |> should.be_true
}
