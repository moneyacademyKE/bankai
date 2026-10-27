//// Operator commands for explicit replica trust provisioning.
//// Parsing is shared with socket/MCP so every transport has the same contract.

import bankai/sync/trust as sync_trust
import bankai/sync/trust_args
import bankai/sync_peer
import bankai/time
import gleam/json
import gleam/list
import gleam/result

pub fn sync_identity_cmd(workspace: String) -> Result(json.Json, String) {
  use key <- result.try(sync_peer.public_key(workspace))
  Ok(
    json.object([
      #("workspace", json.string(workspace)),
      #("public_key", json.string(key)),
    ]),
  )
}

/// Trust is always explicit. An optional expiry limits the key without changing
/// the default behavior of existing provisioning commands.
pub fn sync_trust_cmd(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  use key <- result.try(
    list.first(args)
    |> result.replace_error("usage: sync trust <public-key> [--expires-at NS]"),
  )
  use expires_at <- result.try(trust_args.expiry_args(list.drop(args, 1)))
  use Nil <- result.try(sync_trust.trust_workspace_key_for(
    workspace,
    key,
    0,
    expires_at,
  ))
  Ok(
    json.object([
      #("trusted", json.string(key)),
      #("expires_at", json.int(expires_at)),
      #("workspace", json.string(workspace)),
    ]),
  )
}

pub fn sync_revoke_cmd(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  use key <- result.try(
    list.first(args)
    |> result.replace_error("usage: sync revoke <public-key>"),
  )
  use Nil <- result.try(sync_peer.revoke_peer(workspace, key))
  Ok(
    json.object([
      #("revoked", json.string(key)),
      #("workspace", json.string(workspace)),
    ]),
  )
}

pub fn sync_rotate_cmd(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  use #(old_id, new_id, rest) <- result.try(case args {
    [old_id, new_id, ..rest] -> Ok(#(old_id, new_id, rest))
    _ ->
      Error(
        "usage: sync rotate <old-key> <new-key> [--overlap NS] [--expires-at NS]",
      )
  })
  use #(overlap, expires_at) <- result.try(trust_args.rotation_args(rest))
  let now = time.now()
  use Nil <- result.try(sync_trust.rotate_workspace_keys_at(
    workspace,
    old_id,
    new_id,
    now,
    overlap,
    expires_at,
  ))
  Ok(
    json.object([
      #("rotated_from", json.string(old_id)),
      #("trusted", json.string(new_id)),
      #("overlap", json.int(overlap)),
      #("expires_at", json.int(expires_at)),
      #("workspace", json.string(workspace)),
    ]),
  )
}
