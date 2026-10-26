//// Focused regressions for the causal-sync and recovery gaps (bk-09cd).
////
//// Each test names one defect and fails on the current tree:
////   1. replica decoding marks a signature applied BEFORE the authoritative
////      import, so a rejected import can never be retried;
////   2. daemon backup restore rewrites JSONL while Mnesia, the live authority,
////      keeps its old heads;
////   3. a recorded conflict can be deleted without an explicit side choice or
////      any authoritative head write;
////   4. every same-id/different-hash head is treated as divergent, so ordinary
////      fast-forward and stale peers are rejected instead of reconciled.

import bankai/ast_bridge
import bankai/backup
import bankai/daemon_store
import bankai/mnesia_store
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

fn current_titles(ws: String) -> List(String) {
  case mnesia_store.current_store(ws) {
    Ok(index) ->
      index
      |> store.current_tasks
      |> list.map(fn(task) { task.title })
    Error(_) -> []
  }
}

/// Defect 1: decode is not apply. A verified snapshot may be decoded repeatedly
/// while nothing has been imported; only the import continuation marks it.
pub fn decoding_a_signed_snapshot_does_not_mark_it_applied_test() {
  let sender = "/tmp/bankai_causal_sender_decode"
  let receiver = "/tmp/bankai_causal_receiver_decode"
  wipe(sender)
  wipe(receiver)
  let _ = should.be_ok(daemon_store.boot(sender))
  let _ = should.be_ok(daemon_store.boot(receiver))
  let _ = should.be_ok(daemon_store.create(sender, "Decoded not applied", []))
  let sender_key = should.be_ok(sync_peer.public_key(sender))
  let _ = should.be_ok(sync_peer.trust_peer(receiver, sender_key))
  let frame = should.be_ok(sync_peer.signed_snapshot_for_test(sender))

  let _ =
    should.be_ok(sync_peer.decode_signed_snapshot_for_test(receiver, frame))
  // Nothing was imported yet, so the same verified frame must still decode.
  // Today the first decode already consumed the signature as "applied".
  sync_peer.decode_signed_snapshot_for_test(receiver, frame)
  |> should.be_ok
  |> fn(snapshot) { list.length(snapshot.heads) }
  |> should.equal(1)
}

/// Defect 1, end to end: a pull whose import is rejected must be retryable.
/// The snapshot is verified and decoded, the import fails on divergence, the
/// operator clears the divergent head, and the same peer is pulled again.
pub fn rejected_import_can_be_retried_test() {
  let local = "/tmp/bankai_causal_retry_local"
  let remote = "/tmp/bankai_causal_retry_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id =
    should.be_ok(daemon_store.create(remote, "Remote authoritative work", []))
    |> extract_id

  // Seed a divergent head on the receiver so the first import is rejected.
  let divergent = case mnesia_store.get_current(remote, remote_id) {
    Ok(task) ->
      ast_bridge.rehash(
        types.Task(
          ..task,
          title: "Locally divergent copy",
          updated_at: task.updated_at + 1,
        ),
      )
    Error(_) -> panic as "remote task missing"
  }
  let _ =
    should.be_ok(
      mnesia_store.import_replica_snapshot(local, store.from_list([divergent]), [
        divergent,
      ]),
    )

  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_811) })
  process.sleep(250)

  daemon_store.pull_peer(local, "localhost", 17_811)
  |> should.be_error
  |> string.contains("divergent")
  |> should.be_true

  // Operator archives the divergent head; history keeps both versions.
  let _ =
    should.be_ok(mnesia_store.replace_current_snapshot(
      local,
      store.from_list([]),
    ))

  // Retry must reach the import again instead of being refused as a replay.
  daemon_store.pull_peer(local, "localhost", 17_811)
  |> should.be_ok

  current_titles(local)
  |> list.contains("Remote authoritative work")
  |> should.be_true
}

/// Defect 2: daemon backup restore must write Mnesia, the live authority.
pub fn daemon_backup_restore_writes_authoritative_state_test() {
  let ws = "/tmp/bankai_causal_restore"
  wipe(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let _ = should.be_ok(daemon_store.create(ws, "Restored alpha", []))
  let _ = should.be_ok(daemon_store.create(ws, "Restored beta", []))
  let _ = should.be_ok(daemon_store.backup_jsonl(ws))

  let catalog = should.be_ok(backup.catalog(ws))
  let assert Ok(entry) = list.first(catalog)
  entry.task_count |> should.equal(2)

  // Lose the live authority, exactly as a corrupt/fresh Mnesia would.
  let _ = should.be_ok(mnesia_store.reset_workspace_for_test(ws))
  current_titles(ws) |> list.length |> should.equal(0)

  let _ = should.be_ok(daemon_store.backup_restore(ws, entry.path))

  let restored = current_titles(ws)
  list.length(restored) |> should.equal(2)
  list.contains(restored, "Restored alpha") |> should.be_true
  list.contains(restored, "Restored beta") |> should.be_true
}

/// Defect 2, compatibility half: the JSONL export must agree with the database
/// after a restore, so operators reading the file see the same tasks.
pub fn restored_authoritative_state_exports_consistently_test() {
  let ws = "/tmp/bankai_causal_restore_export"
  wipe(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let _ = should.be_ok(daemon_store.create(ws, "Export agreement", []))
  let _ = should.be_ok(daemon_store.backup_jsonl(ws))
  let catalog = should.be_ok(backup.catalog(ws))
  let assert Ok(entry) = list.first(catalog)
  let _ = should.be_ok(mnesia_store.reset_workspace_for_test(ws))
  let _ = should.be_ok(daemon_store.backup_restore(ws, entry.path))

  case simplifile.read(ws <> "/tasks.jsonl") {
    Ok(text) -> string.contains(text, "Export agreement") |> should.be_true
    Error(_) -> should.fail()
  }
}

/// Defect 3: resolving by id alone is not a resolution. With no side chosen the
/// conflict must survive so the evidence stays available.
pub fn resolving_a_conflict_without_a_side_keeps_the_record_test() {
  let ws = "/tmp/bankai_causal_conflict_side"
  wipe(ws)
  let detail = "task=bk-9001 local=aaaa remote=bbbb"
  let _ = should.be_ok(conflicts.record_conflict(ws, "sync", detail))
  let conflicts = should.be_ok(conflicts.list_conflicts(ws))
  let assert Ok(record) = list.first(conflicts)

  daemon_store.conflicts_resolve(ws, record.id, "")
  |> should.be_error

  conflicts.list_conflicts(ws)
  |> should.be_ok
  |> list.length
  |> should.equal(1)
}

/// Defect 3, second half: a non-merge (legacy/free-form) conflict cannot be
/// resolved automatically, and deleting it would destroy the only evidence.
pub fn resolving_a_non_merge_conflict_keeps_the_record_test() {
  let ws = "/tmp/bankai_causal_conflict_legacy"
  wipe(ws)
  let _ = should.be_ok(conflicts.record_conflict(ws, "peer", "schema mismatch"))
  let conflicts = should.be_ok(conflicts.list_conflicts(ws))
  let assert Ok(record) = list.first(conflicts)

  daemon_store.conflicts_resolve(ws, record.id, "local")
  |> should.be_error

  conflicts.list_conflicts(ws)
  |> should.be_ok
  |> list.length
  |> should.equal(1)
}

/// Defect 4: a remote descendant of the local head is a fast-forward, not a
/// conflict. Today every same-id/different-hash pair is refused.
pub fn pull_peer_fast_forwards_a_descendant_head_test() {
  let local = "/tmp/bankai_causal_ff_local"
  let remote = "/tmp/bankai_causal_ff_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id =
    should.be_ok(daemon_store.create(remote, "Fast forward target", []))
    |> extract_id

  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_812) })
  process.sleep(250)
  let _ = should.be_ok(daemon_store.pull_peer(local, "localhost", 17_812))

  // Remote advances its head; the receiver already holds the ancestor.
  let _ = should.be_ok(daemon_store.update(remote, remote_id, "in_progress"))

  daemon_store.pull_peer(local, "localhost", 17_812)
  |> should.be_ok

  should.be_ok(mnesia_store.get_current(local, remote_id)).status
  |> fn(status) { status == types.InProgress }
  |> should.be_true
}

/// Defect 4, second half: a stale remote head must keep the local descendant
/// instead of blocking the whole import.
pub fn pull_peer_keeps_local_descendant_when_remote_is_stale_test() {
  let local = "/tmp/bankai_causal_stale_local"
  let remote = "/tmp/bankai_causal_stale_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id =
    should.be_ok(daemon_store.create(remote, "Stale remote head", []))
    |> extract_id

  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_813) })
  process.sleep(250)
  let _ = should.be_ok(daemon_store.pull_peer(local, "localhost", 17_813))

  // Local advances past the remote head.
  let _ = should.be_ok(daemon_store.update(local, remote_id, "in_progress"))
  // Remote produces a new snapshot signature without advancing that task.
  let _ = should.be_ok(daemon_store.create(remote, "Unrelated remote task", []))

  daemon_store.pull_peer(local, "localhost", 17_813)
  |> should.be_ok

  should.be_ok(mnesia_store.get_current(local, remote_id)).status
  |> fn(status) { status == types.InProgress }
  |> should.be_true
  current_titles(local)
  |> list.contains("Unrelated remote task")
  |> should.be_true
}

/// Defect 4, divergent half: two unrelated descendants of the same ancestor are
/// a real conflict and must never be auto-merged.
pub fn pull_peer_records_conflict_for_unrelated_descendants_test() {
  let local = "/tmp/bankai_causal_div_local"
  let remote = "/tmp/bankai_causal_div_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let remote_id =
    should.be_ok(daemon_store.create(remote, "Shared ancestor", []))
    |> extract_id

  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_814) })
  process.sleep(250)
  let _ = should.be_ok(daemon_store.pull_peer(local, "localhost", 17_814))

  // Both sides advance the same task independently.
  let _ = should.be_ok(daemon_store.update(remote, remote_id, "in_progress"))
  let _ = should.be_ok(daemon_store.update(local, remote_id, "blocked"))

  daemon_store.pull_peer(local, "localhost", 17_814)
  |> should.be_error

  let conflicts = should.be_ok(conflicts.list_conflicts(local))
  conflicts
  |> list.any(fn(record) { string.contains(record.detail, remote_id) })
  |> should.be_true
  // Local head is untouched by a rejected import.
  should.be_ok(mnesia_store.get_current(local, remote_id)).status
  |> fn(status) { status == types.Blocked }
  |> should.be_true
}

/// Pin: a first pull with no shared history is a plain union, not a conflict.
pub fn pull_peer_unions_disjoint_histories_test() {
  let local = "/tmp/bankai_causal_union_local"
  let remote = "/tmp/bankai_causal_union_remote"
  wipe(local)
  wipe(remote)
  let _ = should.be_ok(daemon_store.boot(local))
  let _ = should.be_ok(daemon_store.boot(remote))
  let _ = should.be_ok(daemon_store.create(local, "Local only work", []))
  let _ = should.be_ok(daemon_store.create(remote, "Remote only work", []))

  let remote_key = should.be_ok(sync_peer.public_key(remote))
  let _ = should.be_ok(sync_peer.trust_peer(local, remote_key))
  let _ = process.spawn_unlinked(fn() { sync_peer.serve(remote, 17_815) })
  process.sleep(250)
  let _ = should.be_ok(daemon_store.pull_peer(local, "localhost", 17_815))

  let titles = current_titles(local)
  list.contains(titles, "Local only work") |> should.be_true
  list.contains(titles, "Remote only work") |> should.be_true
  Nil
}
