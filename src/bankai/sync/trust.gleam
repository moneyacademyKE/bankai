//// Bankai's adapter for gleamunison's pure signer trust policy.
////
//// Signer ids are canonical Base64 Ed25519 public keys. AaronDB still verifies
//// signatures; this module owns only key lifecycle and admission.

import bankai/time
import gleam/list
import gleam/result
import gleamunison/evidence
import gleamunison/trust.{type TrustPolicy}

/// Legacy keys have no expiry metadata, so migration preserves their access.
pub const no_expiry = 9_223_372_036_854_775_807

@external(erlang, "bankai_replica_ffi", "read_trust_policy")
fn ffi_read_policy(
  workspace: String,
) -> Result(#(List(#(String, Int, Int)), List(String)), String)

@external(erlang, "bankai_replica_ffi", "write_trust_policy")
fn ffi_write_policy(
  workspace: String,
  active: List(#(String, Int, Int)),
  revoked: List(String),
) -> Result(Nil, String)

/// Admit a signer at an explicit Bankai nanosecond wall-clock timestamp.
pub fn admit_key(
  policy: TrustPolicy,
  signer_id: String,
  now: Int,
) -> Result(Nil, String) {
  trust.key_admits(policy, signer_id, now)
  |> result.map(fn(_) { Nil })
  |> result.map_error(trust.refusal_name)
}

/// Replace every state for a signer with one explicit active validity window.
/// An operator's explicit upsert may re-admit a previously revoked key.
pub fn upsert_active(
  policy: TrustPolicy,
  signer_id: String,
  since: Int,
  until: Int,
) -> Result(TrustPolicy, String) {
  case since >= 0 && until > since {
    False -> Error("trust validity window requires 0 <= since < until")
    True ->
      Ok(
        trust.policy([
          trust.active(signer(signer_id), since, until),
          ..without_signer(policy, signer_id)
        ]),
      )
  }
}

/// Replace every state for a signer with a revocation tombstone.
pub fn revoke(policy: TrustPolicy, signer_id: String) -> TrustPolicy {
  trust.policy([
    trust.revoked(signer(signer_id)),
    ..without_signer(policy, signer_id)
  ])
}

/// Rotate an active signer to a different key with a bounded overlap. The old
/// key never gains validity beyond its existing expiry; the new key starts now.
pub fn rotate(
  policy: TrustPolicy,
  old_id: String,
  new_id: String,
  now: Int,
  overlap: Int,
  new_until: Int,
) -> Result(TrustPolicy, String) {
  case old_id == new_id {
    True -> Error("sync rotation requires distinct old and new keys")
    False ->
      case overlap >= 0 && new_until > now {
        False ->
          Error("sync rotation requires overlap >= 0 and new expiry > now")
        True -> {
          use old_key <- result.try(
            trust.key_admits(policy, old_id, now)
            |> result.map_error(trust.refusal_name),
          )
          case old_key.state {
            trust.Revoked -> Error(trust.refusal_name(trust.KeyRevoked(old_id)))
            trust.Active(old_since, old_until) -> {
              let old_expiry = case old_until < now + overlap {
                True -> old_until
                False -> now + overlap
              }
              let retained =
                policy
                |> without_signer(old_id)
                |> list.filter(fn(key) { key.signer.id != new_id })
              Ok(
                trust.policy([
                  trust.active(signer(old_id), old_since, old_expiry),
                  trust.active(signer(new_id), now, new_until),
                  ..retained
                ]),
              )
            }
          }
        }
      }
  }
}

fn without_signer(
  policy: TrustPolicy,
  signer_id: String,
) -> List(trust.TrustedKey) {
  list.filter(policy.keys, fn(key) { key.signer.id != signer_id })
}

fn signer(signer_id: String) -> evidence.Signer {
  // key_admits uses only the stable id. Replica and gate signatures are Ed25519
  // and never pass through gleamunison's HMAC evidence admission function.
  evidence.signer(signer_id, <<>>)
}

/// Load the versioned policy, or migrate the two legacy flat key lists in memory.
pub fn load(workspace: String) -> Result(TrustPolicy, String) {
  use #(active, revoked) <- result.try(ffi_read_policy(workspace))
  let active_keys =
    active
    |> list.filter(fn(entry) {
      let #(signer_id, _, _) = entry
      !list.contains(revoked, signer_id)
    })
    |> list.map(fn(entry) {
      let #(signer_id, since, until) = entry
      trust.active(signer(signer_id), since, until)
    })
  let revoked_keys =
    list.map(revoked, fn(signer_id) { trust.revoked(signer(signer_id)) })
  Ok(trust.policy(list.append(active_keys, revoked_keys)))
}

fn save(workspace: String, policy: TrustPolicy) -> Result(Nil, String) {
  let #(active, revoked) =
    list.fold(policy.keys, #([], []), fn(acc, key) {
      let #(active, revoked) = acc
      case key.state {
        trust.Active(since, until) -> #(
          [#(key.signer.id, since, until), ..active],
          revoked,
        )
        trust.Revoked -> #(active, [key.signer.id, ..revoked])
      }
    })
  ffi_write_policy(workspace, list.reverse(active), list.reverse(revoked))
}

/// Preserve the original always-valid trust operation for existing callers.
pub fn trust_workspace_key(
  workspace: String,
  signer_id: String,
) -> Result(Nil, String) {
  trust_workspace_key_for(workspace, signer_id, 0, no_expiry)
}

/// Trust a key for an explicit validity window, replacing any prior state.
pub fn trust_workspace_key_for(
  workspace: String,
  signer_id: String,
  since: Int,
  until: Int,
) -> Result(Nil, String) {
  use policy <- result.try(load(workspace))
  use updated <- result.try(upsert_active(policy, signer_id, since, until))
  save(workspace, updated)
}

pub fn revoke_workspace_key(
  workspace: String,
  signer_id: String,
) -> Result(Nil, String) {
  use policy <- result.try(load(workspace))
  save(workspace, revoke(policy, signer_id))
}

pub fn rotate_workspace_keys(
  workspace: String,
  old_id: String,
  new_id: String,
  overlap: Int,
  new_until: Int,
) -> Result(Nil, String) {
  rotate_workspace_keys_at(
    workspace,
    old_id,
    new_id,
    time.now(),
    overlap,
    new_until,
  )
}

pub fn rotate_workspace_keys_at(
  workspace: String,
  old_id: String,
  new_id: String,
  now: Int,
  overlap: Int,
  new_until: Int,
) -> Result(Nil, String) {
  use policy <- result.try(load(workspace))
  use updated <- result.try(rotate(
    policy,
    old_id,
    new_id,
    now,
    overlap,
    new_until,
  ))
  save(workspace, updated)
}

/// Production replica verification uses wall-clock nanoseconds, never the
/// envelope's change-feed offset. Tests use the explicit-timestamp variant.
pub fn admit_workspace_key(
  workspace: String,
  signer_id: String,
) -> Result(Nil, String) {
  admit_workspace_key_at(workspace, signer_id, time.now())
}

pub fn admit_workspace_key_at(
  workspace: String,
  signer_id: String,
  now: Int,
) -> Result(Nil, String) {
  use policy <- result.try(load(workspace))
  admit_key(policy, signer_id, now)
}

/// Current admissibility plus whether the key has an explicit tombstone.
pub fn workspace_key_status_at(
  workspace: String,
  signer_id: String,
  now: Int,
) -> Result(#(Bool, Bool), String) {
  use policy <- result.try(load(workspace))
  let revoked =
    list.any(policy.keys, fn(key) {
      key.signer.id == signer_id && key.state == trust.Revoked
    })
  Ok(#(result.is_ok(admit_key(policy, signer_id, now)), revoked))
}
