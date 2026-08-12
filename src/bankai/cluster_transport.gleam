//// Cluster transport configuration and admission policy.
////
//// AaronDB owns the typed identity checks. Bankai keeps the project-specific
//// configuration file small, explicit, and free of private key material. The
//// BEAM distribution channel itself must already be configured with TLS; this
//// module refuses to label an unconfigured clustered daemon as healthy.

import aarondb/identity
import bankai/platform_profile.{type Profile}
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import simplifile

pub const filename = "cluster-transport.json"

pub type Peer {
  Peer(node_id: String, fingerprint: String)
}

pub type Config {
  Config(
    schema_version: Int,
    cluster_id: String,
    node_id: String,
    issuer: String,
    local_fingerprint: String,
    members: List(Peer),
    max_rpc_bytes: Int,
    max_attempts: Int,
    timeout_ms: Int,
  )
}

pub type TransportStatus {
  Ready(config: Config)
  RecoveryRequired(reason: String)
  NotApplicable
}

pub fn path(workspace: String) -> String {
  workspace <> "/.bankai/" <> filename
}

/// A local profile has no cluster transport to configure. An explicit clustered
/// profile must carry a matching authenticated-transport configuration before
/// `bankai serve` will accept cluster traffic.
pub fn require_ready(
  workspace: String,
  profile: Profile,
) -> Result(Nil, String) {
  case profile.mode, profile.cluster_id, profile.node_id {
    platform_profile.Local, _, _ -> Ok(Nil)
    platform_profile.Clustered, option.Some(cluster_id), option.Some(node_id) ->
      load(workspace)
      |> result.try(fn(config) { validate_binding(config, cluster_id, node_id) })
      |> result.try(validate_identity)
    platform_profile.Clustered, _, _ ->
      Error("cluster transport requires a valid clustered platform profile")
  }
}

pub fn diagnose(workspace: String, profile: Profile) -> TransportStatus {
  case profile.mode, profile.cluster_id, profile.node_id {
    platform_profile.Local, _, _ -> NotApplicable
    platform_profile.Clustered, option.Some(cluster_id), option.Some(node_id) ->
      case
        load(workspace)
        |> result.try(fn(config) {
          validate_binding(config, cluster_id, node_id)
        })
        |> result.try(validate_identity)
      {
        Ok(_) ->
          case load(workspace) {
            Ok(config) -> Ready(config)
            Error(reason) -> RecoveryRequired(reason)
          }
        Error(reason) -> RecoveryRequired(reason)
      }
    platform_profile.Clustered, _, _ ->
      RecoveryRequired("clustered platform profile has no stable node identity")
  }
}

pub fn status_json(status: TransportStatus) -> json.Json {
  case status {
    NotApplicable ->
      json.object([
        #("state", json.string("not-applicable")),
        #("transport", json.string("none")),
      ])
    RecoveryRequired(reason) ->
      json.object([
        #("state", json.string("recovery-required")),
        #("transport", json.string("beam-distribution-tls")),
        #("error", json.string(reason)),
      ])
    Ready(config) ->
      json.object([
        #("state", json.string("configured")),
        #("transport", json.string("beam-distribution-tls")),
        #("cluster_id", json.string(config.cluster_id)),
        #("node_id", json.string(config.node_id)),
        #("members", json.int(list.length(config.members))),
        #("max_rpc_bytes", json.int(config.max_rpc_bytes)),
        #("max_attempts", json.int(config.max_attempts)),
        #("timeout_ms", json.int(config.timeout_ms)),
      ])
  }
}

fn load(workspace: String) -> Result(Config, String) {
  case simplifile.read(from: path(workspace)) {
    Ok(contents) -> from_json(contents)
    Error(_) -> Error("cluster transport configuration is missing")
  }
}

fn from_json(contents: String) -> Result(Config, String) {
  case json.parse(from: contents, using: decoder()) {
    Ok(config) -> Ok(config)
    Error(_) -> Error("invalid Bankai cluster transport configuration")
  }
}

fn decoder() -> decode.Decoder(Config) {
  use schema_version <- decode.field("schema_version", decode.int)
  use cluster_id <- decode.field("cluster_id", decode.string)
  use node_id <- decode.field("node_id", decode.string)
  use issuer <- decode.field("issuer", decode.string)
  use local_fingerprint <- decode.field("local_fingerprint", decode.string)
  use members <- decode.field("members", decode.list(of: peer_decoder()))
  use max_rpc_bytes <- decode.field("max_rpc_bytes", decode.int)
  use max_attempts <- decode.field("max_attempts", decode.int)
  use timeout_ms <- decode.field("timeout_ms", decode.int)
  case
    validate(Config(
      schema_version:,
      cluster_id:,
      node_id:,
      issuer:,
      local_fingerprint:,
      members:,
      max_rpc_bytes:,
      max_attempts:,
      timeout_ms:,
    ))
  {
    Ok(config) -> decode.success(config)
    Error(reason) -> decode.failure(placeholder(), reason)
  }
}

fn peer_decoder() -> decode.Decoder(Peer) {
  use node_id <- decode.field("node_id", decode.string)
  use fingerprint <- decode.field("fingerprint", decode.string)
  decode.success(Peer(node_id:, fingerprint:))
}

fn validate(config: Config) -> Result(Config, String) {
  case
    config.schema_version == 1
    && config.cluster_id != ""
    && config.node_id != ""
    && config.issuer != ""
    && config.local_fingerprint != ""
    && config.max_rpc_bytes > 0
    && config.max_rpc_bytes <= 16_777_216
    && config.max_attempts > 0
    && config.max_attempts <= 10
    && config.timeout_ms > 0
    && config.timeout_ms <= 30_000
    && local_member_is_present(config)
    && member_ids_are_unique(config.members)
  {
    True -> Ok(config)
    False ->
      Error("cluster transport configuration violates Bankai safety limits")
  }
}

fn validate_binding(
  config: Config,
  cluster_id: String,
  node_id: String,
) -> Result(Config, String) {
  case config.cluster_id == cluster_id && config.node_id == node_id {
    True -> Ok(config)
    False ->
      Error("cluster transport identity does not match the platform profile")
  }
}

/// Use AaronDB's admission model even for the local node. This validates the
/// config's issuer, active certificate, membership, and RPC bounds before any
/// transport adapter may send a cluster RPC.
fn validate_identity(config: Config) -> Result(Nil, String) {
  let members = config.members |> list.map(fn(peer) { peer.node_id })
  let store = identity.new(config.cluster_id, [config.issuer], members)
  let store =
    identity.put_certificate(
      store,
      identity.Certificate(
        config.node_id,
        config.local_fingerprint,
        config.issuer,
        identity.Active(1),
      ),
    )
  identity.admit_peer(
    store,
    config.node_id,
    config.local_fingerprint,
    identity.RpcLimits(config.max_rpc_bytes, config.max_attempts),
    0,
  )
  |> result.map_error(identity_error)
}

fn local_member_is_present(config: Config) -> Bool {
  list.any(config.members, fn(peer) {
    peer.node_id == config.node_id
    && peer.fingerprint == config.local_fingerprint
  })
}

fn member_ids_are_unique(members: List(Peer)) -> Bool {
  case members {
    [] -> True
    [Peer(node_id, _), ..rest] ->
      !list.any(rest, fn(peer) { peer.node_id == node_id })
      && member_ids_are_unique(rest)
  }
}

fn identity_error(error: identity.PeerError) -> String {
  case error {
    identity.UnknownCertificate -> "cluster transport certificate is unknown"
    identity.WrongCertificate(_, _) ->
      "cluster transport certificate names another node"
    identity.UntrustedIssuer(_) -> "cluster transport issuer is not trusted"
    identity.InactiveCertificate -> "cluster transport certificate is inactive"
    identity.RevokedCertificate -> "cluster transport certificate is revoked"
    identity.UnauthorizedMember(_) -> "cluster transport node is not a member"
    identity.InvalidRpcSize(_, _) -> "cluster transport RPC size is invalid"
    identity.InvalidReconnectLimit ->
      "cluster transport reconnect policy is invalid"
    identity.ReconnectExhausted(_) ->
      "cluster transport reconnect budget is exhausted"
    identity.BootstrapDenied -> "cluster transport bootstrap is not authorized"
  }
}

fn placeholder() -> Config {
  Config(1, "", "", "", "", [], 1, 1, 1)
}
