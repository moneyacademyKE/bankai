import bankai/daemon_store
import bankai/gate_wisp/store as lifecycle_store
import bankai/gates/facts
import bankai/gates/service as gates
import bankai/mnesia_store
import bankai/time
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

const gate_id = "deploy-production"

const observed_at = 1000

const expires_at = 2000

const valid_now = 1500

pub fn main() {
  gleeunit.main()
}

fn workspaces(name: String) -> #(String, String) {
  let signer = "/tmp/bankai_gate_fact_" <> name <> "_signer"
  let receiver = "/tmp/bankai_gate_fact_" <> name <> "_receiver"
  let _ = facts.reset_for_test(signer)
  let _ = facts.reset_for_test(receiver)
  #(signer, receiver)
}

fn trusted_wire(name: String) -> #(String, String, facts.Wire) {
  let #(signer, receiver) = workspaces(name)
  let issuer = should.be_ok(facts.public_key(signer))
  let _ = should.be_ok(facts.trust_issuer(receiver, issuer))
  let wire =
    should.be_ok(facts.sign(
      signer,
      gate_id,
      facts.Satisfied,
      observed_at,
      expires_at,
    ))
  #(receiver, issuer, wire)
}

pub fn valid_fact_verifies_test() {
  let #(receiver, issuer, wire) = trusted_wire("valid")
  let verified =
    should.be_ok(facts.verify(receiver, wire, gate_id, issuer, valid_now))

  let facts.Wire(_, _, _, _, _, wire_author, wire_signature) = wire
  let facts.Fact(
    verified_gate,
    state,
    verified_observed_at,
    verified_expires_at,
    author,
    signature,
  ) = verified

  verified_gate |> should.equal(gate_id)
  state |> should.equal(facts.Satisfied)
  verified_observed_at |> should.equal(observed_at)
  verified_expires_at |> should.equal(expires_at)
  author |> should.equal(wire_author)
  signature |> should.equal(wire_signature)
}

pub fn tampered_fact_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("tampered")
  let facts.Wire(
    domain,
    signed_gate,
    state,
    signed_observed_at,
    signed_expires_at,
    author,
    signature,
  ) = wire
  let tampered =
    facts.Wire(
      domain,
      signed_gate,
      state,
      signed_observed_at,
      signed_expires_at + 1,
      author,
      signature,
    )

  facts.verify(receiver, tampered, gate_id, issuer, valid_now)
  |> should.be_error
  |> string.contains("signature")
  |> should.be_true
}

pub fn wrong_gate_and_issuer_are_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("wrong_expected")

  facts.verify(receiver, wire, "different-gate", issuer, valid_now)
  |> should.be_error
  |> string.contains("wrong gate")
  |> should.be_true

  let #(other_signer, _) = workspaces("wrong_issuer")
  let other_issuer = should.be_ok(facts.public_key(other_signer))
  facts.verify(receiver, wire, gate_id, other_issuer, valid_now)
  |> should.be_error
  |> string.contains("wrong gate fact issuer")
  |> should.be_true
}

pub fn wrong_domain_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("wrong_domain")
  let facts.Wire(
    _,
    signed_gate,
    state,
    signed_observed_at,
    signed_expires_at,
    author,
    signature,
  ) = wire
  let wrong_domain =
    facts.Wire(
      "bankai-replica-v2",
      signed_gate,
      state,
      signed_observed_at,
      signed_expires_at,
      author,
      signature,
    )

  facts.verify(receiver, wrong_domain, gate_id, issuer, valid_now)
  |> should.be_error
  |> string.contains("domain")
  |> should.be_true
}

pub fn expired_fact_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("expired")

  facts.verify(receiver, wire, gate_id, issuer, expires_at)
  |> should.be_error
  |> string.contains("expired")
  |> should.be_true
}

pub fn future_observation_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("future")

  facts.verify(receiver, wire, gate_id, issuer, observed_at - 1)
  |> should.be_error
  |> string.contains("future")
  |> should.be_true
}

pub fn unknown_issuer_is_rejected_test() {
  let #(signer, receiver) = workspaces("unknown")
  let issuer = should.be_ok(facts.public_key(signer))
  let wire =
    should.be_ok(facts.sign(
      signer,
      gate_id,
      facts.Satisfied,
      observed_at,
      expires_at,
    ))

  facts.verify(receiver, wire, gate_id, issuer, valid_now)
  |> should.be_error
  |> string.contains("unknown")
  |> should.be_true
}

pub fn malformed_signature_encoding_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("malformed")
  let facts.Wire(
    domain,
    signed_gate,
    state,
    signed_observed_at,
    signed_expires_at,
    author,
    signature,
  ) = wire
  let malformed =
    facts.Wire(
      domain,
      signed_gate,
      state,
      signed_observed_at,
      signed_expires_at,
      author,
      signature <> "x",
    )

  facts.verify(receiver, malformed, gate_id, issuer, valid_now)
  |> should.be_error
  |> string.contains("malformed")
  |> should.be_true
}

pub fn verified_external_fact_ingestion_is_audited_test() {
  let signer = "/tmp/bankai_gate_fact_ingestion_signer"
  let receiver = "/tmp/bankai_gate_fact_ingestion_receiver"
  let _ = facts.reset_for_test(signer)
  let _ = facts.reset_for_test(receiver)
  let _ = mnesia_store.init(receiver)
  let _ = mnesia_store.reset_workspace_for_test(receiver)
  let _ = lifecycle_store.init(receiver)
  let _ = lifecycle_store.reset_workspace_for_test(receiver)
  let gate_json =
    should.be_ok(
      daemon_store.create(receiver, "Adapter gate", ["--kind", "gate"]),
    )
  let gate_id =
    gate_json
    |> json.to_string
    |> string.split("\"id\":\"")
    |> fn(parts) {
      let assert [_, tail, ..] = parts
      let assert [found, ..] = string.split(tail, "\"")
      found
    }
  let issuer = should.be_ok(facts.public_key(signer))
  let _ = should.be_ok(facts.trust_issuer(receiver, issuer))
  let now = time.now()
  let wire =
    should.be_ok(facts.sign(
      signer,
      gate_id,
      facts.Satisfied,
      now,
      now + 1_000_000_000,
    ))

  should.be_ok(gates.ingest_fact(receiver, gate_id, issuer, facts.encode(wire)))
  |> json.to_string
  |> string.contains("\"persisted\":true")
  |> should.be_true
  let audits = should.be_ok(lifecycle_store.gate_audits(receiver, gate_id))
  list.length(audits) |> should.equal(1)
  let assert [audit] = audits
  audit.action |> should.equal("signed_fact")
  audit.actor |> should.equal(issuer)
}

pub fn revoked_issuer_is_rejected_test() {
  let #(receiver, issuer, wire) = trusted_wire("revoked")
  let _ = should.be_ok(facts.revoke_issuer(receiver, issuer))

  facts.verify(receiver, wire, gate_id, issuer, valid_now)
  |> should.be_error
  |> string.contains("revoked")
  |> should.be_true
}
