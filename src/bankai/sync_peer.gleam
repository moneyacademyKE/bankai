//// TCP replication of Bankai's authoritative immutable task history.
////
//// A replica is one versioned JSON document: every immutable version plus the
//// sender's explicit current heads. This is intentionally not a head-only
//// transport; history remains inspectable after convergence.

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
import gleam/string

pub const default_port = 7654

const protocol = "bankai-replica-v1"

pub type Snapshot {
  Snapshot(versions: List(types.Task), heads: List(types.Task))
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
        <> " (immutable-history replication)",
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
  let snapshot = case mnesia_store.version_store(workspace) {
    Ok(versions) ->
      Snapshot(
        versions: versions |> store.list() |> without_wisps(),
        heads: case mnesia_store.current_store(workspace) {
          Ok(heads) -> heads |> store.current_tasks() |> without_wisps()
          Error(_) -> []
        },
      )
    Error(_) -> Snapshot(versions: [], heads: [])
  }
  let _ = ffi_send(connection, snapshot_json(snapshot) <> "\n")
  let _ = ffi_close(connection)
  Nil
}

fn without_wisps(tasks: List(types.Task)) -> List(types.Task) {
  list.filter(tasks, fn(task) { task.kind != types.Wisp })
}

pub fn fetch(host: String, port: Int) -> Result(Snapshot, String) {
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
        Ok(line) -> decode_snapshot(line)
        Error(_) -> Error("sync peer closed without a replica snapshot")
      }
      let _ = ffi_close(connection)
      response
    }
  }
}

fn snapshot_json(snapshot: Snapshot) -> String {
  json.to_string(
    json.object([
      #("protocol", json.string(protocol)),
      #("versions", json.array(snapshot.versions, of: serde.task_to_json)),
      #("heads", json.array(snapshot.heads, of: serde.task_to_json)),
    ]),
  )
}

fn decode_snapshot(line: String) -> Result(Snapshot, String) {
  case json.parse(from: string.trim(line), using: snapshot_decoder()) {
    Ok(snapshot) -> Ok(snapshot)
    Error(_) ->
      Error(
        "incompatible sync peer response: expected bankai-replica-v1 snapshot",
      )
  }
}

fn snapshot_decoder() -> decode.Decoder(Snapshot) {
  use advertised_protocol <- decode.field("protocol", decode.string)
  use versions <- decode.field(
    "versions",
    decode.list(of: serde.task_decoder()),
  )
  use heads <- decode.field("heads", decode.list(of: serde.task_decoder()))
  case advertised_protocol == protocol {
    True -> decode.success(Snapshot(versions:, heads:))
    False -> decode.failure(Snapshot(versions: [], heads: []), protocol)
  }
}
