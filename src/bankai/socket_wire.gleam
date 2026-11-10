//// The socket wire layer: JSON codec, UNIX-socket FFI, and the client.
//// Pure line-in/line-out plus transport; no daemon policy lives here.

import bankai/service_auth
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/json
import gleam/result
import gleam/string

const socket_filename = "bankai.sock"

pub fn socket_path(workspace: String) -> String {
  workspace <> "/" <> socket_filename
}

// ---------------------------------------------------------------------------
// Public protocol entry point (pure, tested) — dispatches to the CLI ops.
// ---------------------------------------------------------------------------
pub fn parse_request(
  line: String,
) -> Result(#(String, List(String), Int), Nil) {
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

pub fn ok_response(value: String, id: Int) -> String {
  json.object([#("result", json.string(value)), #("id", json.int(id))])
  |> json.to_string()
}

pub fn error_response(message: String, id: Int) -> String {
  json.object([#("error", json.string(message)), #("id", json.int(id))])
  |> json.to_string()
}

pub fn extract_result(line: String) -> Result(String, String) {
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
pub fn ffi_listen(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "accept")
pub fn ffi_accept(ls: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "recv_line")
pub fn ffi_recv_line(sock: Dynamic) -> Result(String, Dynamic)

/// Client-side bounded recv, WIRED (bk-06d1): {error, timeout} after
/// Timeout ms instead of an infinite block when the daemon stalls —
/// "daemon did not reply within 30s" is now a true statement. The daemon
/// accept loop keeps unbounded recv_line (idle connections must stay open).
///
/// The historical full-suite Badarg is fixed at the FFI layer:
/// gen_tcp can deliver {packet, line} data as an Erlang list, and Gleam's
/// <> compiles to binary concatenation — a list operand crashed. The FFI
/// now normalizes (strip_eol + iolist_to_binary), matching recv_line.
@external(erlang, "bankai_socket_ffi", "recv_line_t")
pub fn ffi_recv_line_t(sock: Dynamic, timeout: Int) -> Result(String, Dynamic)

@external(erlang, "bankai_socket_ffi", "send_data")
pub fn ffi_send(sock: Dynamic, data: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "close_s")
pub fn ffi_close(sock: Dynamic) -> Nil

@external(erlang, "bankai_socket_ffi", "connect")
pub fn ffi_connect(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "delete_path")
pub fn ffi_delete_path(path: String) -> Nil

@external(erlang, "bankai_socket_ffi", "controlling_process")
pub fn ffi_controlling_process(
  sock: Dynamic,
  pid: process.Pid,
) -> Result(Dynamic, Dynamic)

pub fn client_request(
  workspace: String,
  method: String,
  params: List(String),
) -> Result(String, String) {
  service_auth.local_admin_token(workspace)
  |> result.try(fn(token) {
    client_request_with_token(workspace, method, params, token)
  })
}

/// Recv helper: gen_tcp {packet, line} with no buffer option delivers a reply
/// longer than the recv buffer as several partial "lines". Once the task store
/// grew past ~4KB, the single recv here returned a mid-JSON fragment and every
/// read died as "malformed daemon response" — masked upstream as
/// "daemon required". Accumulate chunks until the whole line parses or the
/// daemon closes the socket. Bounded: each chunk wait is capped at 30s
/// (recv_line_t), so a stalled daemon yields "daemon did not reply within
/// 30s" instead of hanging the client forever.
fn recv_full_response(sock: Dynamic, acc: String) -> Result(String, Dynamic) {
  case ffi_recv_line_t(sock, 30_000) {
    Ok(chunk) -> {
      let line = acc <> chunk
      case extract_result(line) {
        Ok(_) -> Ok(line)
        Error(_) -> recv_full_response(sock, line)
      }
    }
    Error(reason) ->
      case acc {
        "" -> Error(reason)
        _ -> Ok(acc)
      }
  }
}

/// Send an attenuated request to the resident service. The token is included in
/// the request only; errors and responses never echo bearer credentials.
pub fn client_request_with_token(
  workspace: String,
  method: String,
  params: List(String),
  token: String,
) -> Result(String, String) {
  case ffi_connect(socket_path(workspace)) {
    Error(_) -> Error("no daemon (not reachable; may still be starting)")
    Ok(sock) -> {
      let req =
        json.object([
          #("method", json.string(method)),
          #("params", json.array(params, of: json.string)),
          #("token", json.string(token)),
          #("id", json.int(1)),
        ])
        |> json.to_string()
      let _ = ffi_send(sock, req <> "\n")
      let response = recv_full_response(sock, "")
      let _ = ffi_close(sock)
      case response {
        Ok(line) -> extract_result(line)
        Error(_) ->
          Error("daemon did not reply within 30s (may still be starting)")
      }
    }
  }
}
