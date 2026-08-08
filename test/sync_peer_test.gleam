import bankai/daemon_store
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/sync_peer
import gleam/erlang/process
import gleam/json
import gleam/list
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
pub fn pull_imports_remote_tasks_through_transactional_store_test() {
  let local = "/tmp/bankai_livesync_local"
  let remote = "/tmp/bankai_livesync_remote"
  wipe(local)
  wipe(remote)
  let _ = daemon_store.boot(local)
  let _ = daemon_store.boot(remote)
  let _ = daemon_store.create(local, "Local only", [])
  let _ = daemon_store.create(remote, "Remote only", [])

  // The peer server is read-only over Mnesia. The receiving daemon performs
  // the only write through its transactional repository.
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_661) })
  process.sleep(200)
  let out = should.be_ok(daemon_store.pull_peer(local, "localhost", 17_661))
  json.to_string(out)
  |> string.contains("reconciled transactional store")
  |> should.be_true

  let current = should.be_ok(mnesia_store.current_store(local))
  let rendered =
    current
    |> store.current_tasks
    |> list.map(serde.task_to_json_string)
    |> string.join("\n")
  rendered |> string.contains("Local only") |> should.be_true
  rendered |> string.contains("Remote only") |> should.be_true
}

/// sync-pull to a port with no listener is a clean error envelope, not a crash.
pub fn pull_with_no_peer_is_an_error_test() {
  let ws = "/tmp/bankai_livesync_nopeer"
  wipe(ws)
  let _ = daemon_store.boot(ws)
  daemon_store.pull_peer(ws, "localhost", 17_699)
  |> should.be_error
  |> string.contains("could not connect")
  |> should.be_true
}
