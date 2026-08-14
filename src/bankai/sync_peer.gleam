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
  Snapshot(versions: List(types.Task), heads: List(types.Task), author: String)
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

@external(erlang, "bankai_replica_ffi", "record_conflict")
fn ffi_record_conflict(
  workspace: String,
  author: String,
  detail: String,
) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "list_conflicts")
fn ffi_list_conflicts(workspace: String) -> Result(String, String)

@external(erlang, "bankai_replica_ffi", "resolve_conflict")
fn ffi_resolve_conflict(
  workspace: String,
  conflict_id: String,
) -> Result(Nil, String)

@external(erlang, "bankai_replica_ffi", "clear_conflicts")
fn ffi_clear_conflicts(workspace: String) -> Result(Nil, String)

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
    |> result.unwrap(
      "{\"protocol\":\"bankai-replica-v2\",\"error\":\"signing failed\"}",
    )
  let _ = ffi_send(connection, message <> "\n")
  let _ = ffi_close(connection)
  Nil
}

fn snapshot_payload(workspace: String) -> Result(#(String, Int), String) {
  mnesia_store.projection_snapshot_rows(workspace)
  |> result.try(fn(pair) {
    let #(offset, heads) = pair
    mnesia_store.version_store(workspace)
    |> result.map(fn(versions) {
      #(
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
          ]),
        ),
        offset,
      )
    })
  })
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
    Error(_) ->
      Error(
        "incompatible sync peer response: expected bankai-replica-v2 envelope",
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
          |> result.try(fn(snapshot) {
            ffi_mark_applied(workspace, signature)
            |> result.map(fn(_) { Snapshot(..snapshot, author:) })
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
  case advertised_protocol == payload_protocol {
    True -> decode.success(Snapshot(versions:, heads:, author: ""))
    False ->
      decode.failure(
        Snapshot(versions: [], heads: [], author: ""),
        payload_protocol,
      )
  }
}

/// Domain conflicts are never silently imported. The conflict record is a
/// durable audit artifact outside the task-head tables, so causal evidence is
/// preserved even when the current materialization cannot advance.
pub fn record_conflict(
  workspace: String,
  author: String,
  detail: String,
) -> Result(Nil, String) {
  ffi_record_conflict(workspace, author, detail)
}

pub type ConflictRecord {
  ConflictRecord(id: String, timestamp: Int, author: String, detail: String)
}

fn conflict_record_decoder() -> decode.Decoder(ConflictRecord) {
  use id <- decode.field("id", decode.string)
  use timestamp <- decode.field("timestamp", decode.int)
  use author <- decode.field("author", decode.string)
  use detail <- decode.field("detail", decode.string)
  decode.success(ConflictRecord(id:, timestamp:, author:, detail:))
}

pub fn list_conflicts(
  workspace: String,
) -> Result(List(ConflictRecord), String) {
  use raw <- result.try(ffi_list_conflicts(workspace))
  json.parse(from: raw, using: decode.list(of: conflict_record_decoder()))
  |> result.map_error(fn(_) { "failed to decode conflict records" })
}

pub fn resolve_conflict(
  workspace: String,
  conflict_id: String,
) -> Result(Nil, String) {
  ffi_resolve_conflict(workspace, conflict_id)
}

pub fn clear_conflicts(workspace: String) -> Result(Nil, String) {
  ffi_clear_conflicts(workspace)
}
