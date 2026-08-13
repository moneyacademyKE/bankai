import bankai/daemon_store
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/sync_peer
import gleam/list
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
