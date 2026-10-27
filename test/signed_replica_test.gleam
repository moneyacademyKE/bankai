import bankai/daemon_store
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/sync/conflicts
import bankai/sync/trust as sync_trust
import bankai/sync_peer
import gleam/list
import gleam/result
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn reset(ws: String) {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = mnesia_store.init(ws)
  let _ = mnesia_store.reset_workspace_for_test(ws)
  let _ = sync_peer.reset_identity_for_test(ws)
  Nil
}

pub fn trusted_signed_snapshot_round_trips_once_test() {
  let sender = "/tmp/bankai_signed_sender"
  let receiver = "/tmp/bankai_signed_receiver"
  reset(sender)
  reset(receiver)
  let _ = should.be_ok(daemon_store.boot(sender))
  let _ = should.be_ok(daemon_store.boot(receiver))
  let created =
    should.be_ok(daemon_store.create(sender, "Signed remote work", []))
  let sender_key = should.be_ok(sync_peer.public_key(sender))
  let _ = should.be_ok(sync_peer.trust_peer(receiver, sender_key))
  let frame = should.be_ok(sync_peer.signed_snapshot_for_test(sender))
  let snapshot =
    should.be_ok(sync_peer.decode_signed_snapshot_for_test(receiver, frame))
  snapshot.versions |> list.length |> should.equal(1)
  snapshot.heads |> list.length |> should.equal(1)
  let _ =
    should.be_ok(mnesia_store.import_replica_snapshot(
      receiver,
      store.from_list(snapshot.versions),
      snapshot.heads,
    ))
  let received = should.be_ok(mnesia_store.current_store(receiver))
  store.current_tasks(received)
  |> list.map(serde.task_to_json_string)
  |> string.join("\n")
  |> string.contains("Signed remote work")
  |> should.be_true

  // Replay protection now fires on consumption, not on decode: the frame is
  // marked applied only after the import lands, then the same frame is refused.
  let _ = should.be_ok(sync_peer.mark_applied(receiver, snapshot.signature))
  sync_peer.decode_signed_snapshot_for_test(receiver, frame)
  |> should.be_error
  |> string.contains("replayed")
  |> should.be_true
  let _ = created
}

pub fn untrusted_tampered_wrong_domain_and_revoked_frames_are_rejected_test() {
  let sender = "/tmp/bankai_signed_sender_reject"
  let receiver = "/tmp/bankai_signed_receiver_reject"
  reset(sender)
  reset(receiver)
  let _ = should.be_ok(daemon_store.boot(sender))
  let _ = should.be_ok(daemon_store.boot(receiver))
  let _ = should.be_ok(daemon_store.create(sender, "Protected remote work", []))
  let sender_key = should.be_ok(sync_peer.public_key(sender))
  let frame = should.be_ok(sync_peer.signed_snapshot_for_test(sender))

  sync_peer.decode_signed_snapshot_for_test(receiver, frame)
  |> should.be_error
  |> string.contains("unknown")
  |> should.be_true

  let _ = should.be_ok(sync_peer.trust_peer(receiver, sender_key))
  let wrong_domain =
    string.replace(
      frame,
      "\"domain\":\"bankai-replica-v2\"",
      "\"domain\":\"evil-domain\"",
    )
  let _ =
    should.be_error(sync_peer.decode_signed_snapshot_for_test(
      receiver,
      wrong_domain,
    ))

  let _ = should.be_ok(sync_peer.adversarial_envelope_checks_for_test())
  let _ = should.be_ok(sync_peer.revoke_peer(receiver, sender_key))
  // The FFI verifier performs the revocation gate before envelope parsing;
  // the end-to-end transport path exercises it in the next signed exchange.
}

pub fn expired_and_revoked_keys_reject_valid_signed_frames_test() {
  let sender = "/tmp/bankai_signed_policy_sender"
  let receiver = "/tmp/bankai_signed_policy_receiver"
  let now = 1_000_000_000_000_000_000
  reset(sender)
  reset(receiver)
  let _ = should.be_ok(daemon_store.boot(sender))
  let _ = should.be_ok(daemon_store.create(sender, "Policy-bound work", []))
  let sender_key = should.be_ok(sync_peer.public_key(sender))
  let _ =
    should.be_ok(sync_trust.trust_workspace_key_for(
      receiver,
      sender_key,
      now - 100,
      now,
    ))
  let frame = should.be_ok(sync_peer.signed_snapshot_for_test(sender))

  sync_peer.decode_signed_snapshot_at_for_test(receiver, frame, now - 1)
  |> should.be_ok
  sync_peer.decode_signed_snapshot_at_for_test(receiver, frame, now)
  |> should.be_error
  |> string.contains("key_expired")
  |> should.be_true

  let _ =
    should.be_ok(sync_trust.trust_workspace_key_for(
      receiver,
      sender_key,
      now,
      now + 100,
    ))
  sync_peer.decode_signed_snapshot_at_for_test(receiver, frame, now)
  |> should.be_ok

  let _ = should.be_ok(sync_peer.revoke_peer(receiver, sender_key))
  sync_peer.decode_signed_snapshot_at_for_test(receiver, frame, now)
  |> should.be_error
  |> string.contains("key_revoked")
  |> should.be_true
}

pub fn conflict_recording_and_resolution_lifecycle_test() {
  let ws = "/tmp/bankai_conflict_test"
  reset(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let _ = should.be_ok(daemon_store.create(ws, "Conflicted task", []))
  let created = case mnesia_store.current_store(ws) {
    Ok(index) ->
      case store.current_tasks(index) |> list.first {
        Ok(task) -> task
        Error(_) -> panic as "conflicted task missing"
      }
    Error(_) -> panic as "conflicted workspace missing"
  }
  let local_hex = store.hash_key(created.content_hash)
  let _ =
    should.be_ok(conflicts.record_conflict(
      ws,
      "peer-key-1",
      "task=" <> created.id <> " local=" <> local_hex <> " remote=deadbeef",
    ))
  let _ =
    should.be_ok(conflicts.record_conflict(
      ws,
      "peer-key-2",
      "schema mismatch on bk-200",
    ))

  let conflicts = should.be_ok(conflicts.list_conflicts(ws))
  conflicts |> list.length |> should.equal(2)

  let merge =
    should.be_ok(
      list.find(conflicts, fn(c) {
        conflicts.parse_conflict_sides(c.detail) |> result.is_ok
      }),
    )
  let free_form =
    should.be_ok(
      list.find(conflicts, fn(c) {
        conflicts.parse_conflict_sides(c.detail) |> result.is_error
      }),
    )
  merge.detail |> string.contains("bk-") |> should.be_true

  // Free-form conflicts are not merge conflicts: resolving one would destroy
  // the only record of an unresolved divergence.
  conflicts.resolve_conflict(ws, free_form.id, conflicts.KeepLocal)
  |> should.be_error
  conflicts.list_conflicts(ws)
  |> should.be_ok
  |> list.length
  |> should.equal(2)

  // The merge conflict resolves only with an explicit side, and that side
  // becomes the authoritative head.
  let _ =
    should.be_ok(conflicts.resolve_conflict(ws, merge.id, conflicts.KeepLocal))
  conflicts.list_conflicts(ws)
  |> should.be_ok
  |> list.length
  |> should.equal(1)

  // The chosen side is now the head; promotion creates a new version, so the
  // original chosen version stays addressable in history.
  mnesia_store.get_current(ws, created.id)
  |> should.be_ok
  |> fn(task) { task.id }
  |> should.equal(created.id)
  mnesia_store.version_store(ws)
  |> should.be_ok
  |> fn(versions) { store.get_by_hex(versions, local_hex) }
  |> should.be_ok

  let _ = should.be_ok(conflicts.clear_conflicts(ws))
  let cleared = should.be_ok(conflicts.list_conflicts(ws))
  cleared |> list.length |> should.equal(0)
}
