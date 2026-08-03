//// The daemon transport + protocol layer (warm path for the sub-5ms NFR).
////
//// A resident daemon (`bankai serve`) listens on .bankai/bankai.sock and
//// answers line-delimited JSON-RPC requests without paying the BEAM cold-start
//// cost of a single-shot `gleam run` per command. The dominant latency for the
//// single-shot path is process/VM boot; the daemon keeps that paid once.
////
//// Transport = gen_tcp over a UNIX-domain socket (bankai_socket_ffi.erl).
//// Protocol = one JSON request line -> one JSON response line, reusing the same
//// ops as the CLI via `handle_request`. `handle_request` stays the pure,
//// testable protocol entry point; `serve`/`client_request` add the wire.

import bankai/cli
import bankai/sync/jsonl
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/io
import gleam/json
import gleam/string

pub type Request {
  Request(method: String, params: List(String))
}

pub type Response {
  OkResponse(value: String)
  ErrorResponse(message: String)
}

const socket_filename = "bankai.sock"

pub fn socket_path(workspace: String) -> String {
  workspace <> "/" <> socket_filename
}

// ---------------------------------------------------------------------------
// Public protocol entry point (pure, tested) — dispatches to the CLI ops.
// ---------------------------------------------------------------------------

pub fn handle_request(workspace: String, request: Request) -> Response {
  case request.method {
    "ready" -> OkResponse(value: cli.run_in(workspace, ["ready"]))
    "list" -> OkResponse(value: cli.run_in(workspace, ["list"]))
    "create" ->
      case request.params {
        [title, ..] ->
          OkResponse(value: cli.run_in(workspace, ["create", title]))
        _ -> ErrorResponse(message: "create requires a title")
      }
    "update" ->
      case request.params {
        [id, status, ..] ->
          OkResponse(value: cli.run_in(workspace, ["update", id, status]))
        _ -> ErrorResponse(message: "update requires <id> <status>")
      }
    "inspect" ->
      case request.params {
        [hash, ..] ->
          OkResponse(value: cli.run_in(workspace, ["inspect", hash]))
        _ -> ErrorResponse(message: "inspect requires a hash")
      }
    "prime" -> OkResponse(value: cli.run_in(workspace, ["prime"]))
    "sync" -> OkResponse(value: cli.run_in(workspace, ["sync"]))
    "init" -> OkResponse(value: cli.run_in(workspace, ["init"]))
    _ -> ErrorResponse(message: "unknown method: " <> request.method)
  }
}

// ---------------------------------------------------------------------------
// Wire layer: parse a JSON-RPC line, dispatch, emit a JSON-RPC response line.
// ---------------------------------------------------------------------------

/// Handle one raw request line -> one response line (JSON).
pub fn handle_line(workspace: String, line: String) -> String {
  case parse_request(line) {
    Error(_) -> error_response("parse error", 0)
    Ok(#(method, params, id)) -> {
      let resp = handle_request(workspace, Request(method:, params:))
      case resp {
        OkResponse(value) -> ok_response(value, id)
        ErrorResponse(message) -> error_response(message, id)
      }
    }
  }
}

fn parse_request(line: String) -> Result(#(String, List(String), Int), Nil) {
  case json.parse(from: string.trim(line), using: request_decoder()) {
    Ok(req) -> Ok(req)
    Error(_) -> Error(Nil)
  }
}

fn request_decoder() -> decode.Decoder(#(String, List(String), Int)) {
  use method <- decode.field("method", decode.string)
  use params <- decode.field("params", decode.list(of: decode.string))
  use id <- decode.field("id", decode.int)
  decode.success(#(method, params, id))
}

fn ok_response(value: String, id: Int) -> String {
  json.object([#("result", json.string(value)), #("id", json.int(id))])
  |> json.to_string()
}

fn error_response(message: String, id: Int) -> String {
  json.object([#("error", json.string(message)), #("id", json.int(id))])
  |> json.to_string()
}

fn extract_result(line: String) -> Result(String, String) {
  case json.parse(from: string.trim(line), using: response_decoder()) {
    Ok(#(result, error)) ->
      case error == "" {
        True -> Ok(result)
        False -> Error(error)
      }
    Error(_) -> Error("malformed daemon response")
  }
}

fn response_decoder() -> decode.Decoder(#(String, String)) {
  use result <- decode.optional_field("result", "", decode.string)
  use error <- decode.optional_field("error", "", decode.string)
  decode.success(#(result, error))
}

// ---------------------------------------------------------------------------
// Transport (FFI): gen_tcp over a UNIX-domain socket.
// ---------------------------------------------------------------------------

@external(erlang, "bankai_socket_ffi", "listen")
fn ffi_listen(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "accept")
fn ffi_accept(ls: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "recv_line")
fn ffi_recv_line(sock: Dynamic) -> Result(String, Dynamic)

@external(erlang, "bankai_socket_ffi", "send_data")
fn ffi_send(sock: Dynamic, data: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "close_s")
fn ffi_close(sock: Dynamic) -> Nil

@external(erlang, "bankai_socket_ffi", "connect")
fn ffi_connect(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "delete_path")
fn ffi_delete_path(path: String) -> Nil

@external(erlang, "bankai_socket_ffi", "controlling_process")
fn ffi_controlling_process(
  sock: Dynamic,
  pid: process.Pid,
) -> Result(Dynamic, Dynamic)

// ---------------------------------------------------------------------------
// Daemon: `bankai serve` — blocks in an accept loop.
// ---------------------------------------------------------------------------

/// Start the daemon: listen on <workspace>/bankai.sock and serve forever.
pub fn serve(workspace: String) -> Nil {
  let _ = jsonl.ensure_dir(workspace)
  let path = socket_path(workspace)
  let _ = ffi_delete_path(path)
  case ffi_listen(path) {
    Error(_) -> io.println_error("bankai: failed to listen on " <> path)
    Ok(ls) -> {
      io.println("bankai daemon listening on " <> path)
      serve_loop(workspace, ls)
    }
  }
}

fn serve_loop(workspace: String, ls: Dynamic) -> Nil {
  case ffi_accept(ls) {
    Error(_) -> Nil
    Ok(sock) -> {
      // Isolate each connection: a handler crash must not kill the accept loop.
      // BUG-05 fix: hand socket control to the handler so its lifetime + close
      // signals are tied to the handler (else the socket leaks when a handler
      // dies and error signals route to the acceptor).
      let handler = process.spawn(fn() { handle_conn(workspace, sock) })
      let _ = ffi_controlling_process(sock, handler)
      serve_loop(workspace, ls)
    }
  }
}

fn handle_conn(workspace: String, sock: Dynamic) -> Nil {
  case ffi_recv_line(sock) {
    Ok(line) -> {
      let _ = ffi_send(sock, handle_line(workspace, line) <> "\n")
      Nil
    }
    Error(_) -> Nil
  }
  let _ = ffi_close(sock)
  Nil
}

// ---------------------------------------------------------------------------
// Client: connect to a running daemon and send one request.
// ---------------------------------------------------------------------------

/// Send one request to the daemon over the socket if it's up.
/// Returns Error when no daemon is listening (caller falls back to single-shot).
pub fn client_request(
  workspace: String,
  method: String,
  params: List(String),
) -> Result(String, String) {
  case ffi_connect(socket_path(workspace)) {
    Error(_) -> Error("no daemon")
    Ok(sock) -> {
      let req =
        json.object([
          #("method", json.string(method)),
          #("params", json.array(params, of: json.string)),
          #("id", json.int(1)),
        ])
        |> json.to_string()
      let _ = ffi_send(sock, req <> "\n")
      let result = ffi_recv_line(sock)
      let _ = ffi_close(sock)
      case result {
        Ok(line) -> extract_result(line)
        Error(_) -> Error("no response from daemon")
      }
    }
  }
}
