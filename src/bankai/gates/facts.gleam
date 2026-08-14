//// Signed external evidence for satisfying a Bankai gate.
////
//// This module only authenticates and validates a fact. Persisting it and
//// marking its signature as seen belong to the caller's transaction.

import gleam/dynamic/decode
import gleam/json
import gleam/result

pub const domain = "bankai-gate-fact-v1"

/// The only gate-fact state accepted by this protocol version.
pub type State {
  Satisfied
}

/// The complete signed value exchanged between workspaces.
pub type Wire {
  Wire(
    domain: String,
    gate_id: String,
    state: State,
    observed_at: Int,
    expires_at: Int,
    author: String,
    signature: String,
  )
}

/// A verified fact. Author and signature are retained so the parent can store
/// and replay-mark the evidence in the same transaction as its gate update.
pub type Fact {
  Fact(
    gate_id: String,
    state: State,
    observed_at: Int,
    expires_at: Int,
    author: String,
    signature: String,
  )
}

@external(erlang, "bankai_gate_facts_ffi", "public_key")
fn ffi_public_key(workspace: String) -> Result(String, String)

@external(erlang, "bankai_gate_facts_ffi", "trust_issuer")
fn ffi_trust_issuer(
  workspace: String,
  public_key: String,
) -> Result(Nil, String)

@external(erlang, "bankai_gate_facts_ffi", "revoke_issuer")
fn ffi_revoke_issuer(
  workspace: String,
  public_key: String,
) -> Result(Nil, String)

@external(erlang, "bankai_gate_facts_ffi", "issuer_status")
fn ffi_issuer_status(
  workspace: String,
  public_key: String,
) -> Result(#(Bool, Bool), String)

@external(erlang, "bankai_gate_facts_ffi", "sign")
fn ffi_sign(
  workspace: String,
  gate_id: String,
  state: State,
  observed_at: Int,
  expires_at: Int,
) -> Result(#(String, String, State, Int, Int, String, String), String)

@external(erlang, "bankai_gate_facts_ffi", "verify")
fn ffi_verify(
  workspace: String,
  domain: String,
  gate_id: String,
  state: State,
  observed_at: Int,
  expires_at: Int,
  author: String,
  signature: String,
  expected_gate_id: String,
  expected_issuer: String,
  now: Int,
) -> Result(#(String, State, Int, Int, String, String), String)

@external(erlang, "bankai_gate_facts_ffi", "reset_for_test")
fn ffi_reset_for_test(workspace: String) -> Result(Nil, String)

pub fn public_key(workspace: String) -> Result(String, String) {
  ffi_public_key(workspace)
}

/// Add an issuer's Ed25519 public key to the receiver workspace's explicit
/// trust store. Verification never trusts an issuer as a side effect.
pub fn trust_issuer(
  receiver_workspace: String,
  issuer: String,
) -> Result(Nil, String) {
  ffi_trust_issuer(receiver_workspace, issuer)
}

/// Add an issuer's Ed25519 public key to the receiver workspace's revocation
/// store. Revocation takes precedence if a key is present in both stores.
pub fn revoke_issuer(
  receiver_workspace: String,
  issuer: String,
) -> Result(Nil, String) {
  ffi_revoke_issuer(receiver_workspace, issuer)
}

/// Read explicit local trust/revocation state without attempting verification.
pub fn issuer_status(
  receiver_workspace: String,
  issuer: String,
) -> Result(#(Bool, Bool), String) {
  ffi_issuer_status(receiver_workspace, issuer)
}

/// Sign all gate-fact fields with the workspace's persistent Ed25519 identity.
pub fn sign(
  signer_workspace: String,
  gate_id: String,
  state: State,
  observed_at: Int,
  expires_at: Int,
) -> Result(Wire, String) {
  case ffi_sign(signer_workspace, gate_id, state, observed_at, expires_at) {
    Ok(#(domain, gate_id, state, observed_at, expires_at, author, signature)) ->
      Ok(Wire(
        domain:,
        gate_id:,
        state:,
        observed_at:,
        expires_at:,
        author:,
        signature:,
      ))
    Error(error) -> Error(error)
  }
}

/// Verify domain separation, expected gate and issuer, trust and revocation,
/// validity times, canonical key/signature encodings, and the Ed25519 signature.
/// This function intentionally does not mark the signature as seen.
pub fn verify(
  receiver_workspace: String,
  wire: Wire,
  expected_gate_id: String,
  expected_issuer: String,
  now: Int,
) -> Result(Fact, String) {
  let Wire(domain, gate_id, state, observed_at, expires_at, author, signature) =
    wire

  case
    ffi_verify(
      receiver_workspace,
      domain,
      gate_id,
      state,
      observed_at,
      expires_at,
      author,
      signature,
      expected_gate_id,
      expected_issuer,
      now,
    )
  {
    Ok(#(gate_id, state, observed_at, expires_at, author, signature)) ->
      Ok(Fact(gate_id:, state:, observed_at:, expires_at:, author:, signature:))
    Error(error) -> Error(error)
  }
}

pub fn encode(wire: Wire) -> String {
  let Wire(domain, gate_id, _, observed_at, expires_at, author, signature) =
    wire
  json.object([
    #("domain", json.string(domain)),
    #("gate_id", json.string(gate_id)),
    #("state", json.string("satisfied")),
    #("observed_at", json.int(observed_at)),
    #("expires_at", json.int(expires_at)),
    #("author", json.string(author)),
    #("signature", json.string(signature)),
  ])
  |> json.to_string
}

pub fn decode(value: String) -> Result(Wire, String) {
  json.parse(from: value, using: {
    use wire_domain <- decode.field("domain", decode.string)
    use gate_id <- decode.field("gate_id", decode.string)
    use state <- decode.field("state", decode.string)
    use observed_at <- decode.field("observed_at", decode.int)
    use expires_at <- decode.field("expires_at", decode.int)
    use author <- decode.field("author", decode.string)
    use signature <- decode.field("signature", decode.string)
    case state {
      "satisfied" ->
        decode.success(Wire(
          wire_domain,
          gate_id,
          Satisfied,
          observed_at,
          expires_at,
          author,
          signature,
        ))
      _ ->
        decode.failure(
          Wire(
            wire_domain,
            gate_id,
            Satisfied,
            observed_at,
            expires_at,
            author,
            signature,
          ),
          "satisfied gate fact state",
        )
    }
  })
  |> result.map_error(fn(_) { "gate fact decode failed" })
}

/// Delete this workspace's shared Bankai identity, trust, and revocation files.
/// Intended only for isolated test workspaces.
pub fn reset_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_for_test(workspace)
}
