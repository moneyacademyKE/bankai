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

/// Authenticate and authorize one protocol method. Unknown methods default to
/// read authority, then fail as unknown during dispatch; this avoids turning
/// method classification into an authorization bypass.
pub fn authorize_request(
  workspace: String,
  signed_token: String,
  method: String,
  params: List(String),
) -> Result(Nil, String) {
  use token <- result.try(verify(workspace, signed_token))
  auth.authorize(token, [required_capability(method, params)])
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
) -> auth.Capability {
  let action = case method, params {
    "auth_mint", _ -> auth.Admin
    "ready", ["--claim", ..] -> auth.Write
    "create", _
    | "update", _
    | "merge", _
    | "dep_add", _
    | "backup", _
    | "export", _
    | "import", _
    | "sync", _
    | "sync_pull", _
    | "remember", _
    | "compact", _
    | "rule_register", _
    | "rule_approve", _
    | "rule_revoke", _
    | "rule_eval", _
    | "init", _
    -> auth.Write
    _, _ -> auth.Read
  }
  auth.Capability(action, auth.Database(resource))
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
