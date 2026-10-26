//// Regressions for the conflict-resolution and replica-trust defects found by
//// the post-merge audit (docs/audits/2026-10-26-causal-sync-audit.md).
////
//// Each test names one defect and fails on the audited tree:
////   1. bk-ec1a — a resolved fork is causally orphaned, so the pair can never
////      sync again;
////   2. bk-0f2e — resolution promotes a stale side over a head that moved on;
////   3. bk-5ce5 — promotion replaces the whole head set from a stale read,
////      deleting work written after the read;
////   4. bk-0b66 — every rejected retry appends another record for one fork;
////   5. bk-7d50 — no daemon surface to provision replica trust, so `sync-pull`
////      cannot succeed against a real peer.

import bankai/ast_bridge
import bankai/daemon_store
import bankai/mnesia_store
import bankai/socket
import bankai/storage/authority
import bankai/storage/store
import bankai/sync/conflicts
import bankai/sync_peer
import bankai/types
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

fn wipe(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = mnesia_store.init(ws)
  let _ = mnesia_store.reset_workspace_for_test(ws)
  let _ = sync_peer.reset_identity_for_test(ws)
  Nil
}

fn extract_id(value: json.Json) -> String {
  let rendered = json.to_string(value)
  let assert Ok(#(_, after)) = string.split_once(rendered, "\"id\":\"")
  let assert Ok(#(id, _)) = string.split_once(after, "\"")
  id
}

fn head_hash(ws: String, id: String) -> String {
  let task = should.be_ok(mnesia_store.get_current(ws, id))
  store.hash_key(task.content_hash)
}

fn status_of(ws: String, id: String) -> types.TaskStatus {
  should.be_ok(mnesia_store.get_current(ws, id)).status
}

/// A fork must be refused: pulling it is expected to fail, and the failure is
/// what records the conflict.
fn expect_rejected(pull: Result(json.Json, String)) -> Nil {
  case pull {
    Ok(_) -> should.fail()
    Error(_) -> Nil
  }
}

/// Start a peer serving `remote` and let the caller pull from it.
fn serve_peer(remote: String, port: Int) -> Nil {
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, port) })
  process.sleep(250)
  Nil
}

/// Fork one shared task: both workspaces advance the same id independently.
fn fork_shared_task(local: String, remote: String, port: Int) -> String {
  let remote_id =
    should.be_ok(daemon_store.create(remote, "Shared ancestor", []))
    |> extract_id
  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  serve_peer(remote, port)
  let _ = should.be_ok(daemon_store.pull_peer(local, "localhost", port))
  let _ = should.be_ok(daemon_store.update(remote, remote_id, "in_progress"))
  let _ = should.be_ok(daemon_store.update(local, remote_id, "blocked"))
  remote_id
}

/// bk-ec1a: after resolving a fork, the next pull must succeed. The promoted
/// head has to stay causally connected to both sides; today it is a node with
/// no edges, so the classifier can only answer "divergent" forever.
pub fn resolving_a_fork_makes_the_pair_converge_test() {
  let local = "/tmp/bankai_res_converge_local"
  let remote = "/tmp/bankai_res_converge_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id = fork_shared_task(local, remote, 17_821)

  daemon_store.pull_peer(local, "localhost", 17_821)
  |> should.be_error
  |> string.contains("divergent")
  |> should.be_true

  let recorded = should.be_ok(conflicts.list_conflicts(local))
  let assert Ok(record) = list.first(recorded)
  let _ =
    should.be_ok(daemon_store.conflicts_resolve(local, record.id, "remote"))

  // The pair must be able to sync again, and the chosen side must be the head.
  daemon_store.pull_peer(local, "localhost", 17_821)
  |> should.be_ok
  status_of(local, remote_id)
  |> should.equal(types.InProgress)
}

/// bk-ec1a, keeping local: the same convergence requirement. A `--keep local`
/// resolution also creates a new hash, so it must be linked to both sides too.
pub fn resolving_a_fork_keeping_local_also_converges_test() {
  let local = "/tmp/bankai_res_localwin_local"
  let remote = "/tmp/bankai_res_localwin_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id = fork_shared_task(local, remote, 17_822)

  expect_rejected(daemon_store.pull_peer(local, "localhost", 17_822))

  let recorded = should.be_ok(conflicts.list_conflicts(local))
  let assert Ok(record) = list.first(recorded)
  let _ =
    should.be_ok(daemon_store.conflicts_resolve(local, record.id, "local"))

  daemon_store.pull_peer(local, "localhost", 17_822)
  |> should.be_ok
  status_of(local, remote_id)
  |> should.equal(types.Blocked)
}

/// bk-0f2e: a conflict record names the hashes the sides had when the fork was
/// recorded. If the head moved since, resolution must refuse instead of
/// silently reverting the newer edit.
pub fn resolving_a_conflict_refuses_a_head_that_moved_test() {
  let ws = "/tmp/bankai_res_moved"
  wipe(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let id = should.be_ok(daemon_store.create(ws, "Moved head", [])) |> extract_id
  let forked_at = head_hash(ws, id)

  let detail =
    "task=" <> id <> " local=" <> forked_at <> " remote=" <> fake_hash()
  let _ = should.be_ok(conflicts.record_conflict(ws, "sync", detail))

  // The operator edits the task after the fork was recorded.
  let _ = should.be_ok(daemon_store.update(ws, id, "in_progress"))

  let recorded = should.be_ok(conflicts.list_conflicts(ws))
  let assert Ok(record) = list.first(recorded)

  daemon_store.conflicts_resolve(ws, record.id, "local")
  |> should.be_error
  |> string.contains("changed")
  |> should.be_true

  // The newer edit survives, and the evidence is still there to re-resolve.
  status_of(ws, id) |> should.equal(types.InProgress)
  conflicts.list_conflicts(ws) |> should.be_ok |> list.length |> should.equal(1)
}

/// bk-0f2e, deletion half: a task deleted after the fork was recorded must not
/// be resurrected by a resolution.
pub fn resolving_a_conflict_does_not_resurrect_a_deleted_task_test() {
  let ws = "/tmp/bankai_res_deleted"
  wipe(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let id =
    should.be_ok(daemon_store.create(ws, "Deleted head", [])) |> extract_id
  let forked_at = head_hash(ws, id)

  let detail =
    "task=" <> id <> " local=" <> forked_at <> " remote=" <> fake_hash()
  let _ = should.be_ok(conflicts.record_conflict(ws, "sync", detail))

  let _ =
    should.be_ok(mnesia_store.replace_current_snapshot(ws, store.from_list([])))

  let recorded = should.be_ok(conflicts.list_conflicts(ws))
  let assert Ok(record) = list.first(recorded)

  daemon_store.conflicts_resolve(ws, record.id, "local")
  |> should.be_error

  mnesia_store.get_current(ws, id)
  |> should.be_error
}

/// bk-5ce5: promotion must write one row, not replace the head set from a read
/// taken earlier. A head written after that read has to survive.
pub fn promotion_does_not_delete_a_concurrently_written_head_test() {
  let ws = "/tmp/bankai_res_concurrent"
  wipe(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let alpha = should.be_ok(daemon_store.create(ws, "Alpha", [])) |> extract_id
  let _ = should.be_ok(daemon_store.create(ws, "Beta", []))

  // The head set a resolution would have read before doing its work. It is
  // read here only to prove the shape is irrelevant now: promotion no longer
  // takes a head set at all.
  let stale_heads =
    should.be_ok(mnesia_store.current_store(ws)) |> store.current_tasks
  list.length(stale_heads) |> should.equal(2)

  // Work that lands after that read: a concurrent writer in the daemon.
  let _ = should.be_ok(daemon_store.create(ws, "Concurrent gamma", []))

  let alpha_task = should.be_ok(mnesia_store.get_current(ws, alpha))
  let promoted =
    ast_bridge.rehash(
      types.Task(..alpha_task, updated_at: alpha_task.updated_at + 1),
    )
  let _ =
    should.be_ok(
      authority.promote_version(ws, promoted, [], [head_hash(ws, alpha)]),
    )

  let titles =
    should.be_ok(mnesia_store.current_store(ws))
    |> store.current_tasks
    |> list.map(fn(task) { task.title })
  list.contains(titles, "Concurrent gamma") |> should.be_true
  list.length(titles) |> should.equal(3)
}

/// bk-0b66: a rejected pull is retryable by design, so the retry must not grow
/// the conflict log. One fork is one record.
pub fn repeated_rejected_pulls_record_one_conflict_test() {
  let local = "/tmp/bankai_res_dedupe_local"
  let remote = "/tmp/bankai_res_dedupe_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let _ = fork_shared_task(local, remote, 17_823)

  expect_rejected(daemon_store.pull_peer(local, "localhost", 17_823))
  expect_rejected(daemon_store.pull_peer(local, "localhost", 17_823))
  expect_rejected(daemon_store.pull_peer(local, "localhost", 17_823))

  conflicts.list_conflicts(local)
  |> should.be_ok
  |> list.length
  |> should.equal(1)
}

/// bk-7d50: trust provisioning is the only way `sync-pull` can work against a
/// real peer, so it has to exist on the daemon surface.
pub fn daemon_exposes_replica_identity_and_trust_test() {
  let remote = "/tmp/bankai_res_trust_remote"
  let local = "/tmp/bankai_res_trust_local"
  wipe(remote)
  wipe(local)
  let _ = should.be_ok(daemon_store.boot(remote))
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.create(remote, "Trusted pull", []))

  let remote_key = should.be_ok(sync_peer.public_key(remote))

  case socket.handle_request(remote, socket.Request("sync_identity", [])) {
    socket.OkResponse(value) ->
      string.contains(value, remote_key) |> should.be_true
    socket.ErrorResponse(message) -> panic as message
  }

  case
    socket.handle_request(local, socket.Request("sync_trust", [remote_key]))
  {
    socket.OkResponse(_) -> Nil
    socket.ErrorResponse(message) -> panic as message
  }

  serve_peer(remote, 17_824)
  case
    socket.handle_request(
      local,
      socket.Request("sync_pull", [
        "--host",
        "localhost",
        "--port",
        "17824",
      ]),
    )
  {
    socket.OkResponse(_) -> Nil
    socket.ErrorResponse(message) -> panic as message
  }

  should.be_ok(mnesia_store.current_store(local))
  |> store.current_tasks
  |> list.map(fn(task) { task.title })
  |> list.contains("Trusted pull")
  |> should.be_true

  // Revocation must be reachable the same way, and must take effect.
  case
    socket.handle_request(local, socket.Request("sync_revoke", [remote_key]))
  {
    socket.OkResponse(_) -> Nil
    socket.ErrorResponse(message) -> panic as message
  }
  case
    socket.handle_request(
      local,
      socket.Request("sync_pull", [
        "--host",
        "localhost",
        "--port",
        "17824",
      ]),
    )
  {
    socket.OkResponse(_) -> should.fail()
    socket.ErrorResponse(message) ->
      string.contains(message, "revoked") |> should.be_true
  }
}

fn fake_hash() -> String {
  string.repeat("ab", 32)
}
