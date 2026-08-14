//// Capability authentication for Bankai's resident service.
////
//// AaronDB supplies the authority vocabulary and subsumption policy. Bankai
//// authenticates provenance first: capability claims are HMAC-signed with a
//// workspace-local 0600 secret, expire, and are then decoded/authorized by
//// `aarondb/auth`. Domain handlers never receive credentials.

import aarondb/auth
import bankai/time
import gleam/bit_array
import gleam/crypto
import gleam/dynamic/decode
import gleam/json
import gleam/result
import gleam/string

pub type Access {
  ReadOnly
  WriteOnly
  Administrator
}

const issuer = "bankai"

const resource = "bankai"

const default_ttl_seconds = 3600

const max_ttl_seconds = 2_592_000

@external(erlang, "bankai_service_auth_ffi", "ensure_secret")
fn ensure_secret(path: String) -> Result(BitArray, String)

@external(erlang, "bankai_service_auth_ffi", "reset_secret")
fn reset_secret(path: String) -> Nil

/// Mint a signed, expiring capability token. The workspace secret never leaves
/// this module; callers receive only an attenuated bearer capability.
pub fn mint(
  workspace: String,
  role: String,
  ttl_seconds: Int,
) -> Result(String, String) {
  use access <- result.try(access_from_string(role))
  case ttl_seconds <= 0 || ttl_seconds > max_ttl_seconds {
    True -> Error("token ttl must be between 1 and 2592000 seconds")
    False -> {
      use secret <- result.try(secret(workspace))
      let token_id =
        crypto.strong_random_bytes(16)
        |> bit_array.base64_url_encode(False)
      let payload = token_payload(access, token_id, now_seconds() + ttl_seconds)
      Ok(crypto.sign_message(
        bit_array.from_string(payload),
        secret,
        crypto.Sha256,
      ))
    }
  }
}

pub fn mint_default(workspace: String, role: String) -> Result(String, String) {
  mint(workspace, role, default_ttl_seconds)
}

/// Local CLI requests bootstrap with a short-lived admin capability derived
/// from the workspace secret. The secret itself is never put on the wire.
pub fn local_admin_token(workspace: String) -> Result(String, String) {
  mint(workspace, "admin", 300)
}

/// Authenticate and authorize one protocol method. Every dispatched method has
/// an explicit policy; unknown methods fail closed before dispatch.
pub fn authorize_request(
  workspace: String,
  signed_token: String,
  method: String,
  params: List(String),
) -> Result(Nil, String) {
  use required <- result.try(required_capability(method, params))
  use token <- result.try(verify(workspace, signed_token))
  auth.authorize(token, [required])
  |> result.map_error(fn(_) { "capability denied for method: " <> method })
}

pub fn access_from_string(role: String) -> Result(Access, String) {
  case string.lowercase(role) {
    "read" -> Ok(ReadOnly)
    "write" -> Ok(WriteOnly)
    "admin" -> Ok(Administrator)
    _ -> Error("capability role must be read, write, or admin")
  }
}

pub fn reset_for_test(workspace: String) -> Nil {
  reset_secret(secret_path(workspace))
}

fn verify(
  workspace: String,
  signed_token: String,
) -> Result(auth.Token, String) {
  use _ <- result.try(case string.starts_with(signed_token, "SFMyNTY.") {
    True -> Ok(Nil)
    False -> Error("capability token algorithm must be HS256")
  })
  use secret <- result.try(secret(workspace))
  use payload_bits <- result.try(
    crypto.verify_signed_message(signed_token, secret)
    |> result.map_error(fn(_) { "invalid capability signature" }),
  )
  use payload <- result.try(
    bit_array.to_string(payload_bits)
    |> result.map_error(fn(_) { "capability payload is not utf-8" }),
  )
  use claims <- result.try(decode_claims(payload))
  let #(token_issuer, expires_at) = claims
  case token_issuer != issuer, expires_at <= now_seconds() {
    True, _ -> Error("capability issuer is not trusted")
    _, True -> Error("capability token has expired")
    False, False ->
      auth.decode_token(payload)
      |> result.map_error(fn(_) { "invalid capability payload" })
  }
}

fn required_capability(
  method: String,
  params: List(String),
) -> Result(auth.Capability, String) {
  let action = case method, params {
    "auth_mint", _ -> Ok(auth.Admin)
    "ready", ["--claim", ..] -> Ok(auth.Write)
    "gate_resolve", _
    | "gate_fact_ingest", _
    | "wisp_promote", _
    | "wisp_burn", _
    | "wisp_gc", _
    | "create", _
    | "update", _
    | "batch", _
    | "merge", _
    | "dep_add", _
    | "dep_remove", _
    | "backup", _
    | "backup_restore", _
    | "backup_prune", _
    | "sync_conflict_resolve", _
    | "sync_conflict_clear", _
    | "export", _
    | "import", _
    | "sync", _
    | "sync_pull", _
    | "remember", _
    | "compact", _
    | "init", _
    | "rule_register", _
    | "rule_approve", _
    | "rule_revoke", _
    | "rule_eval", _
    | "molecule_register", _
    | "molecule_instantiate", _
    | "molecule_compose", _
    -> Ok(auth.Write)
    "ready", _
    | "backup_list", _
    | "backup_preview", _
    | "sync_conflicts", _
    | "journal_tail", _
    | "gate_list", _
    | "gate_show", _
    | "gate_check", _
    | "wisp_list", _
    | "wisp_digest", _
    | "wisp_archive", _
    | "list", _
    | "dep_list", _
    | "dep_tree", _
    | "dep_traverse", _
    | "dep_graph", _
    | "dep_check", _
    | "doctor", _
    | "cluster_status", _
    | "memories", _
    | "show", _
    | "count", _
    | "blocked", _
    | "cycles", _
    | "duplicates", _
    | "stale", _
    | "history", _
    | "analytics", _
    | "search", _
    | "prime_query", _
    | "epic", _
    | "inspect", _
    | "rule_list", _
    | "rule_show", _
    | "rule_audit", _
    | "molecule_list", _
    | "molecule_show", _
    | "molecule_instance", _
    | "molecule_provenance", _
    | "molecule_progress", _
    | "molecule_current", _
    | "molecule_distill", _
    -> Ok(auth.Read)
    _, _ -> Error("unknown service method: " <> method)
  }
  action
  |> result.map(fn(required_action) {
    auth.Capability(required_action, auth.Database(resource))
  })
}

fn token_payload(access: Access, id: String, expires_at: Int) -> String {
  json.object([
    #("id", json.string(id)),
    #("iss", json.string(issuer)),
    #("exp", json.int(expires_at)),
    #("caps", json.array([capability_json(access)], of: fn(value) { value })),
  ])
  |> json.to_string
}

fn capability_json(access: Access) -> json.Json {
  let operation = case access {
    ReadOnly -> "read"
    WriteOnly -> "write"
    Administrator -> "admin"
  }
  json.object([
    #("op", json.string(operation)),
    #("res", json.string("db:" <> resource)),
  ])
}

fn decode_claims(payload: String) -> Result(#(String, Int), String) {
  json.parse(from: payload, using: {
    use token_issuer <- decode.field("iss", decode.string)
    use expires_at <- decode.field("exp", decode.int)
    decode.success(#(token_issuer, expires_at))
  })
  |> result.map_error(fn(_) { "invalid capability claims" })
}

fn secret(workspace: String) -> Result(BitArray, String) {
  ensure_secret(secret_path(workspace))
}

fn secret_path(workspace: String) -> String {
  workspace <> "/service-auth.key"
}

fn now_seconds() -> Int {
  time.now() / 1_000_000_000
}
