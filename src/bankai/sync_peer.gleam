//// Signed TCP replication of Bankai's authoritative immutable task history.
////
//// The transport moves a signed snapshot payload. Mnesia remains the only
//// receiver-side task authority: envelope verification happens before the
//// transactional import boundary, and a verified conflict is recorded rather
//// than silently choosing a remote head.

import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/types
import bankai/version_graph
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string

pub const default_port = 7654

const envelope_protocol = "bankai-replica-v2"

const payload_protocol = "bankai-replica-payload-v1"

const replica_domain = "bankai-replica-v2"

pub type Snapshot {
  Snapshot(
    versions: List(types.Task),
    heads: List(types.Task),
    /// Causal parent links the sender knows: child hash -> parent hashes.
    /// Content hashes cannot express order, so ancestry must travel with the
    /// snapshot or the receiver cannot tell a fast-forward from a fork.
    ancestry: version_graph.Ancestry,
    author: String,
    signature: String,
  )
}

type EnvelopeWire {
  EnvelopeWire(
    domain: String,
    payload: String,
    author: String,
    parents: List(String),
    logical_clock: Int,
    key_epoch: Int,
    signature: String,
  )
}

@external(erlang, "bankai_replica_ffi", "public_key")
fn ffi_public_key(workspace: String) -> Result(String, String)

@external(erlang, "bankai_replica_ffi", "trust_peer")
fn ffi_trust_peer(workspace: String, public_key: String) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "revoke_peer")
fn ffi_revoke_peer(workspace: String, public_key: String) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "sign_snapshot")
fn ffi_sign_snapshot(
  workspace: String,
  payload: String,
  parents: List(String),
  clock: Int,
) -> Result(String, String)

@external(erlang, "bankai_replica_ffi", "verify_snapshot")
fn ffi_verify_snapshot(
  workspace: String,
  payload: String,
  author: String,
  parents: List(String),
  clock: Int,
  epoch: Int,
  signature: String,
) -> Result(String, String)

@external(erlang, "bankai_replica_ffi", "mark_applied")
fn ffi_mark_applied(workspace: String, signature: String) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "reset_identity_for_test")
fn ffi_reset_identity_for_test(workspace: String) -> Result(Nil, String)

pub fn reset_identity_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_identity_for_test(workspace)
}

@external(erlang, "bankai_replica_ffi", "adversarial_envelope_checks_for_test")
fn ffi_adversarial_envelope_checks_for_test() -> Result(Nil, String)

pub fn adversarial_envelope_checks_for_test() -> Result(Nil, String) {
  ffi_adversarial_envelope_checks_for_test()
}

@external(erlang, "bankai_socket_ffi", "listen_tcp")
fn ffi_listen_tcp(port: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "connect_tcp")
fn ffi_connect_tcp(host: String, port: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "accept")
fn ffi_accept(listener: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "recv_line")
fn ffi_recv_line(socket: Dynamic) -> Result(String, Dynamic)

@external(erlang, "bankai_socket_ffi", "send_data")
fn ffi_send(socket: Dynamic, data: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "close_s")
fn ffi_close(socket: Dynamic) -> Nil

pub fn public_key(workspace: String) -> Result(String, String) {
  ffi_public_key(workspace)
}

/// Trust provisioning is explicit. Receiving an unknown signer never creates a
/// trust entry as a side effect of replication.
pub fn trust_peer(
  workspace: String,
  public_key: String,
) -> Result(Nil, String) {
  ffi_trust_peer(workspace, public_key)
}

pub fn revoke_peer(
  workspace: String,
  public_key: String,
) -> Result(Nil, String) {
  ffi_revoke_peer(workspace, public_key)
}

pub fn parse_port(args: List(String), default: Int) -> Int {
  case args {
    ["--port", value, ..] ->
      case int.parse(value) {
        Ok(port) -> port
        Error(Nil) -> default
      }
    [_, ..rest] -> parse_port(rest, default)
    [] -> default
  }
}

pub fn serve(workspace: String, port: Int) -> Nil {
  let _ = mnesia_store.init(workspace)
  case ffi_listen_tcp(port) {
    Error(_) ->
      io.println_error(
        "bankai sync-serve: failed to listen on port " <> int.to_string(port),
      )
    Ok(listener) -> {
      io.println(
        "bankai sync-serve listening on port "
        <> int.to_string(port)
        <> " (signed immutable-history replication)",
      )
      serve_loop(workspace, listener)
    }
  }
}

fn serve_loop(workspace: String, listener: Dynamic) -> Nil {
  case ffi_accept(listener) {
    Error(_) -> Nil
    Ok(connection) -> {
      send_snapshot(workspace, connection)
      serve_loop(workspace, listener)
    }
  }
}

fn send_snapshot(workspace: String, connection: Dynamic) -> Nil {
  let payload = snapshot_payload(workspace)
  let message =
    payload
    |> result.try(fn(value) {
      ffi_sign_snapshot(workspace, value.0, [], value.1)
    })
    |> result.map_error(fn(reason) {
      json.to_string(
        json.object([
          #("protocol", json.string(envelope_protocol)),
          #("error", json.string(reason)),
        ]),
      )
    })
    |> fn(r) {
      case r {
        Ok(v) -> v
        Error(v) -> v
      }
    }
  let _ = ffi_send(connection, message)
  let _ = ffi_close(connection)
  Nil
}

fn snapshot_payload(workspace: String) -> Result(#(String, Int), String) {
  mnesia_store.projection_snapshot_rows(workspace)
  |> result.try(fn(pair) {
    let #(offset, heads) = pair
    use versions <- result.try(mnesia_store.version_store(workspace))
    use ancestry <- result.try(mnesia_store.ancestry(workspace))
    Ok(#(
      json.to_string(
        json.object([
          #("protocol", json.string(payload_protocol)),
          #("source_offset", json.int(offset)),
          #(
            "versions",
            json.array(
              versions |> store.list() |> without_wisps(),
              of: serde.task_to_json,
            ),
          ),
          #(
            "heads",
            json.array(heads |> without_wisps(), of: serde.task_to_json),
          ),
          #("ancestry", ancestry_json(ancestry)),
        ]),
      ),
      offset,
    ))
  })
}

/// Ancestry rides along as an optional payload field: a peer that does not
/// understand it ignores it, and a snapshot from such a peer decodes with no
/// links (which keeps classification conservative, never optimistic).
fn ancestry_json(ancestry: version_graph.Ancestry) -> json.Json {
  json.array(ancestry, fn(link) {
    let #(hash, parents) = link
    json.object([
      #("hash", json.string(hash)),
      #("parents", json.array(parents, of: json.string)),
    ])
  })
}

fn ancestry_link_decoder() -> decode.Decoder(#(String, List(String))) {
  use hash <- decode.field("hash", decode.string)
  use parents <- decode.field("parents", decode.list(of: decode.string))
  decode.success(#(hash, parents))
}

fn without_wisps(tasks: List(types.Task)) -> List(types.Task) {
  list.filter(tasks, fn(task) { task.kind != types.Wisp })
}

/// Test and local tooling seam: produce the exact signed envelope that
/// `sync-serve` sends, without starting a TCP listener.
pub fn signed_snapshot_for_test(workspace: String) -> Result(String, String) {
  snapshot_payload(workspace)
  |> result.try(fn(value) { ffi_sign_snapshot(workspace, value.0, [], value.1) })
}

/// Test and diagnostic seam. Production callers use `fetch`; this exposes the
/// same verifier so trust/revocation/replay assertions do not need a socket.
pub fn decode_signed_snapshot_for_test(
  workspace: String,
  line: String,
) -> Result(Snapshot, String) {
  decode_signed_snapshot(workspace, line)
}

pub fn fetch(
  host: String,
  port: Int,
  workspace: String,
) -> Result(Snapshot, String) {
  case ffi_connect_tcp(host, port) {
    Error(_) ->
      Error(
        "could not connect to sync peer at "
        <> host
        <> ":"
        <> int.to_string(port),
      )
    Ok(connection) -> {
      let response = case ffi_recv_line(connection) {
        Ok(line) -> decode_signed_snapshot(workspace, line)
        Error(_) -> Error("sync peer closed without a signed replica snapshot")
      }
      let _ = ffi_close(connection)
      response
    }
  }
}

fn decode_signed_snapshot(
  workspace: String,
  line: String,
) -> Result(Snapshot, String) {
  case json.parse(from: string.trim(line), using: envelope_decoder()) {
    Error(reason) ->
      Error(
        "incompatible sync peer response: expected bankai-replica-v2 envelope, decode: "
        <> string.inspect(reason)
        <> ", got: "
        <> string.slice(from: string.trim(line), at_index: 0, length: 400),
      )
    Ok(wire) -> {
      let EnvelopeWire(
        domain,
        payload,
        author,
        parents,
        clock,
        epoch,
        signature,
      ) = wire
      case domain == replica_domain {
        False -> Error("replica envelope rejected: wrong Bankai domain")
        True ->
          ffi_verify_snapshot(
            workspace,
            payload,
            author,
            parents,
            clock,
            epoch,
            signature,
          )
          |> result.try(decode_payload)
          |> result.map(fn(snapshot) {
            Snapshot(..snapshot, author:, signature:)
          })
      }
    }
  }
}

fn decode_payload(payload: String) -> Result(Snapshot, String) {
  case json.parse(from: payload, using: snapshot_decoder()) {
    Ok(snapshot) -> Ok(snapshot)
    Error(_) -> Error("replica envelope carries an invalid Bankai snapshot")
  }
}

fn envelope_decoder() -> decode.Decoder(EnvelopeWire) {
  use advertised_protocol <- decode.field("protocol", decode.string)
  use domain <- decode.field("domain", decode.string)
  use payload <- decode.field("payload", decode.string)
  use author <- decode.field("author", decode.string)
  use parents <- decode.field("parents", decode.list(of: decode.string))
  use logical_clock <- decode.field("logical_clock", decode.int)
  use key_epoch <- decode.field("key_epoch", decode.int)
  use signature <- decode.field("signature", decode.string)
  case advertised_protocol == envelope_protocol {
    True ->
      decode.success(EnvelopeWire(
        domain:,
        payload:,
        author:,
        parents:,
        logical_clock:,
        key_epoch:,
        signature:,
      ))
    False ->
      decode.failure(EnvelopeWire("", "", "", [], -1, 0, ""), envelope_protocol)
  }
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  use advertised_protocol <- decode.field("protocol", decode.string)
  use _source_offset <- decode.field("source_offset", decode.int)
  use versions <- decode.field(
    "versions",
    decode.list(of: serde.task_decoder()),
  )
  use heads <- decode.field("heads", decode.list(of: serde.task_decoder()))
  use ancestry <- decode.optional_field(
    "ancestry",
    [],
    decode.list(of: ancestry_link_decoder()),
  )
  case advertised_protocol == payload_protocol {
    True ->
      decode.success(Snapshot(
        versions:,
        heads:,
        ancestry:,
        author: "",
        signature: "",
      ))
    False ->
      decode.failure(
        Snapshot(
          versions: [],
          heads: [],
          ancestry: [],
          author: "",
          signature: "",
        ),
        payload_protocol,
      )
  }
}

/// Consume a verified envelope's replay token. Callers must invoke this only
/// after the snapshot has been durably imported: a rejected import leaves the
/// token unconsumed, so the same frame can be retried once the operator has
/// cleared the obstacle.
pub fn mark_applied(
  workspace: String,
  signature: String,
) -> Result(Nil, String) {
  ffi_mark_applied(workspace, signature)
}
