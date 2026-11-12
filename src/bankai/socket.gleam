//// The daemon transport + protocol layer. A resident daemon owns the Mnesia
//// write authority; JSONL is no longer a fallback for mutations.

import bankai/cluster_transport
import bankai/daemon_store
import bankai/durable_export
import bankai/platform_profile
import bankai/service_protocol
import bankai/socket_route
import bankai/socket_wire
import bankai/sync/jsonl
import gleam/dynamic.{type Dynamic}
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/result

pub type Request {
  Request(method: String, params: List(String))
}

pub type Response {
  OkResponse(value: String)
  ErrorResponse(message: String)
}

pub fn handle_request(workspace: String, request: Request) -> Response {
  case socket_route.route(workspace, request.method, request.params) {
    Ok(value) -> {
      // Durability pulse: tasks.jsonl stays within one request of the
      // authoritative store, keyed to the changefeed watermark. Export
      // failures are swallowed on purpose — the marker only advances
      // after a successful export, so the next request retries.
      let _ = durable_export.refresh_if_stale(workspace)
      OkResponse(value: json.to_string(json.object([#("ok", value)])))
    }
    Error(message) -> ErrorResponse(message: message)
  }
}

pub fn socket_path(workspace: String) -> String {
  socket_wire.socket_path(workspace)
}

pub fn client_request(
  workspace: String,
  method: String,
  params: List(String),
) -> Result(String, String) {
  socket_wire.client_request(workspace, method, params)
}

pub fn client_request_with_token(
  workspace: String,
  method: String,
  params: List(String),
  token: String,
) -> Result(String, String) {
  socket_wire.client_request_with_token(workspace, method, params, token)
}

pub fn handle_line(workspace: String, line: String) -> String {
  case socket_wire.parse_request(line) {
    Error(_) -> socket_wire.error_response("parse error", 0)
    Ok(#(method, params, id)) -> {
      let resp = handle_request(workspace, Request(method:, params:))
      case resp {
        OkResponse(value) -> socket_wire.ok_response(value, id)
        ErrorResponse(message) -> socket_wire.error_response(message, id)
      }
    }
  }
}

pub fn handle_authenticated_line(workspace: String, line: String) -> String {
  service_protocol.handle_line(workspace, line, fn(method, params) {
    case handle_request(workspace, Request(method:, params:)) {
      OkResponse(value) -> Ok(value)
      ErrorResponse(message) -> Error(message)
    }
  })
}

pub fn serve(workspace: String) -> Nil {
  platform_profile.load(workspace)
  |> result.try(platform_profile.require_local_daemon)
  |> serve_with_profile(workspace, "local")
}

/// Start an explicit clustered daemon. The platform profile and TLS-distribution
/// admission config must agree before command admission can materialize Mnesia
/// state. A bad config fails closed rather than emitting local-only cluster lies.
pub fn serve_clustered(workspace: String) -> Nil {
  platform_profile.load(workspace)
  |> result.try(platform_profile.require_clustered_daemon)
  |> result.try(fn(_) {
    platform_profile.load(workspace)
    |> result.try(fn(profile) {
      cluster_transport.require_ready(workspace, profile)
    })
  })
  |> serve_with_profile(workspace, "clustered")
}

fn serve_with_profile(
  profile: Result(Nil, String),
  workspace: String,
  mode: String,
) -> Nil {
  let _ = jsonl.ensure_dir(workspace)
  case profile, daemon_store.boot(workspace) {
    Error(message), _ ->
      io.println_error("bankai: platform profile failed: " <> message)
    _, Error(message) ->
      io.println_error("bankai: Mnesia boot failed: " <> message)
    Ok(_), Ok(_) -> {
      warm_vector_projection(workspace)
      listen(workspace, mode)
    }
  }
}

fn warm_vector_projection(workspace: String) -> Nil {
  case daemon_store.warm_vector_projection(workspace) {
    Ok(documents) ->
      io.println(
        "bankai vector projection warmed ("
        <> int.to_string(documents)
        <> " documents, queryable)",
      )
    Error(message) ->
      io.println_error("bankai: vector projection warm skipped: " <> message)
  }
}

/// True when a live daemon answers on this socket path. Used to refuse
/// hijacking a workspace another daemon owns (round-4: deleting a live
/// socket and rebinding leaves two daemons with one ledger — split brain).
pub fn socket_owned(path: String) -> Bool {
  case socket_wire.ffi_connect(path) {
    Ok(sock) -> {
      socket_wire.ffi_close(sock)
      True
    }
    Error(_) -> False
  }
}

fn listen(workspace: String, mode: String) -> Nil {
  let path = socket_wire.socket_path(workspace)
  case socket_owned(path) {
    True ->
      io.println_error(
        "bankai: another daemon already owns "
        <> path
        <> " — refusing to hijack it",
      )
    False -> {
      let _ = socket_wire.ffi_delete_path(path)
      case socket_wire.ffi_listen(path) {
        Error(_) -> io.println_error("bankai: failed to listen on " <> path)
        Ok(ls) -> {
          io.println("bankai " <> mode <> " daemon listening on " <> path)
          serve_loop(workspace, ls)
        }
      }
    }
  }
}

fn serve_loop(workspace: String, ls: Dynamic) -> Nil {
  case socket_wire.ffi_accept(ls) {
    Error(_) -> Nil
    Ok(sock) -> {
      // Isolate each connection: a handler crash must not kill the accept loop.
      // BUG-05 fix: hand socket control to the handler so its lifetime + close
      // signals are tied to the handler (else the socket leaks when a handler
      // dies and error signals route to the acceptor).
      let handler = process.spawn(fn() { handle_conn(workspace, sock) })
      let _ = socket_wire.ffi_controlling_process(sock, handler)
      serve_loop(workspace, ls)
    }
  }
}

fn handle_conn(workspace: String, sock: Dynamic) -> Nil {
  case socket_wire.ffi_recv_line(sock) {
    Ok(line) -> {
      let _ =
        socket_wire.ffi_send(
          sock,
          handle_authenticated_line(workspace, line) <> "\n",
        )
      Nil
    }
    Error(_) -> Nil
  }
  let _ = socket_wire.ffi_close(sock)
  Nil
}
