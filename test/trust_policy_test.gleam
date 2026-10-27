import bankai/sync/trust as bankai_trust
import gleam/bit_array
import gleamunison/evidence
import gleamunison/trust
import gleeunit
import gleeunit/should
import simplifile

const now = 1_000_000_000_000_000_000

const far_future = 9_000_000_000_000_000_000

pub fn main() {
  gleeunit.main()
}

fn raw_key(marker: Int) -> BitArray {
  <<0:size(248), marker>>
}

fn key(marker: Int) -> String {
  bit_array.base64_encode(raw_key(marker), True)
}

fn active(marker: Int, since: Int, until: Int) -> trust.TrustedKey {
  trust.active(evidence.signer(key(marker), <<>>), since, until)
}

fn revoked(marker: Int) -> trust.TrustedKey {
  trust.revoked(evidence.signer(key(marker), <<>>))
}

pub fn unknown_signer_has_a_named_refusal_test() {
  bankai_trust.admit_key(trust.policy([]), key(1), now)
  |> should.equal(Error("unknown_signer:" <> key(1)))
}

pub fn revoked_signer_has_a_named_refusal_test() {
  bankai_trust.admit_key(trust.policy([revoked(1)]), key(1), now)
  |> should.equal(Error("key_revoked:" <> key(1)))
}

pub fn not_yet_valid_signer_has_a_named_refusal_test() {
  let policy = trust.policy([active(1, now + 1, now + 100)])
  bankai_trust.admit_key(policy, key(1), now)
  |> should.equal(Error("key_not_yet_valid:" <> key(1)))
}

pub fn expiry_is_exclusive_test() {
  let policy = trust.policy([active(1, now - 100, now)])
  bankai_trust.admit_key(policy, key(1), now - 1)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(policy, key(1), now)
  |> should.equal(Error("key_expired:" <> key(1)))
}

pub fn rotation_overlap_keeps_old_and_new_keys_independent_test() {
  let old = active(1, now - 100, now)
  let new = active(2, now - 10, now + 100)
  let policy = trust.policy([old, new])

  bankai_trust.admit_key(policy, key(1), now - 1)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(policy, key(2), now - 1)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(policy, key(1), now)
  |> should.equal(Error("key_expired:" <> key(1)))
  bankai_trust.admit_key(policy, key(2), now)
  |> should.equal(Ok(Nil))
}

pub fn rotate_moves_trust_with_a_bounded_overlap_test() {
  let policy = trust.policy([active(1, now - 100, now + 50)])
  let rotated =
    should.be_ok(bankai_trust.rotate(policy, key(1), key(2), now, 25, now + 500))

  bankai_trust.admit_key(rotated, key(1), now + 24)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(rotated, key(1), now + 25)
  |> should.equal(Error("key_expired:" <> key(1)))
  bankai_trust.admit_key(rotated, key(2), now)
  |> should.equal(Ok(Nil))
}

pub fn rotate_refuses_unknown_revoked_and_same_key_transitions_test() {
  let empty = trust.policy([])
  bankai_trust.rotate(empty, key(1), key(2), now, 0, no_expiry_for_test())
  |> should.be_error

  let revoked_policy = trust.policy([revoked(1)])
  bankai_trust.rotate(
    revoked_policy,
    key(1),
    key(2),
    now,
    0,
    no_expiry_for_test(),
  )
  |> should.be_error

  let active_policy = trust.policy([active(1, now - 10, now + 100)])
  bankai_trust.rotate(
    active_policy,
    key(1),
    key(1),
    now,
    0,
    no_expiry_for_test(),
  )
  |> should.be_error
}

fn no_expiry_for_test() -> Int {
  9_223_372_036_854_775_807
}

pub fn explicit_upsert_replaces_revocation_test() {
  let policy = trust.policy([revoked(1), active(2, now - 10, now + 100)])
  let updated =
    should.be_ok(bankai_trust.upsert_active(policy, key(1), now - 5, now + 50))

  bankai_trust.admit_key(updated, key(1), now)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(updated, key(2), now)
  |> should.equal(Ok(Nil))
}

pub fn revoke_replaces_an_active_window_test() {
  let policy = trust.policy([active(1, now - 10, now + 100)])
  bankai_trust.revoke(policy, key(1))
  |> bankai_trust.admit_key(key(1), now)
  |> should.equal(Error("key_revoked:" <> key(1)))
}

pub fn invalid_active_windows_are_rejected_test() {
  let policy = trust.policy([])
  bankai_trust.upsert_active(policy, key(1), now, now)
  |> should.be_error
  bankai_trust.upsert_active(policy, key(1), -1, now)
  |> should.be_error
}

@external(erlang, "erlang", "term_to_binary")
fn legacy_terms(keys: List(BitArray)) -> BitArray

pub fn legacy_flat_files_migrate_to_unbounded_active_entries_test() {
  let workspace = "/tmp/bankai_trust_policy_legacy"
  let identity = workspace <> "/identity"
  let _ = simplifile.create_directory_all(identity)
  let _ =
    simplifile.write_bits(
      identity <> "/trusted.term",
      legacy_terms([raw_key(1)]),
    )
  let _ =
    simplifile.write_bits(
      identity <> "/revoked.term",
      legacy_terms([raw_key(2)]),
    )

  let policy = should.be_ok(bankai_trust.load(workspace))
  bankai_trust.admit_key(policy, key(1), far_future)
  |> should.equal(Ok(Nil))
  bankai_trust.admit_key(policy, key(2), now)
  |> should.equal(Error("key_revoked:" <> key(2)))
  bankai_trust.admit_key(policy, key(3), now)
  |> should.equal(Error("unknown_signer:" <> key(3)))
}

pub fn legacy_revocation_wins_over_a_legacy_active_entry_test() {
  let workspace = "/tmp/bankai_trust_policy_legacy_overlap"
  let identity = workspace <> "/identity"
  let _ = simplifile.create_directory_all(identity)
  let _ =
    simplifile.write_bits(
      identity <> "/trusted.term",
      legacy_terms([raw_key(1)]),
    )
  let _ =
    simplifile.write_bits(
      identity <> "/revoked.term",
      legacy_terms([raw_key(1)]),
    )

  should.be_ok(bankai_trust.load(workspace))
  |> bankai_trust.admit_key(key(1), now)
  |> should.equal(Error("key_revoked:" <> key(1)))
}
