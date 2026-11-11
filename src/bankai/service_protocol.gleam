//// Authenticated JSON-line protocol for the resident Bankai service.
////
//// This module owns credential decoding and the authorization gate. The
//// supplied dispatch function receives only method/params data after authority
//// has been established, so domain handlers remain credential-free.

import bankai/service_auth
import bankai/socket_wire
import gleam/dynamic/decode
import gleam/json

pub fn handle_line(
  workspace: String,
  line: String,
  dispatch: fn(String, List(String)) -> Result(String, String),
) -> String {
  case parse_request(line) {
    Error(_) -> socket_wire.error_response("parse error", 0)
    Ok(#(method, params, token, id)) ->
      case token {
        "" -> socket_wire.error_response("missing capability token", id)
        _ ->
          case
            service_auth.authorize_request(workspace, token, method, params)
          {
            Error(message) -> socket_wire.error_response(message, id)
            Ok(Nil) ->
              case dispatch(method, params) {
                Ok(value) -> socket_wire.ok_response(value, id)
                Error(message) -> socket_wire.error_response(message, id)
              }
          }
      }
  }
}

fn parse_request(
  line: String,
) -> Result(#(String, List(String), String, Int), Nil) {
  // socket_wire owns the UTF-8-safe trim. A chunk boundary can split a
  // multi-byte codepoint; that must be an ordinary parse error, not the
  // string.trim badarg crash fixed for the unauthenticated path (bk-4d82).
  case socket_wire.trim_valid(line) {
    Error(Nil) -> Error(Nil)
    Ok(trimmed) ->
      case json.parse(from: trimmed, using: request_decoder()) {
        Ok(request) -> Ok(request)
        Error(_) -> Error(Nil)
      }
  }
}

fn request_decoder() -> decode.Decoder(#(String, List(String), String, Int)) {
  use method <- decode.field("method", decode.string)
  use params <- decode.field("params", decode.list(of: decode.string))
  use token <- decode.optional_field("token", "", decode.string)
  use id <- decode.field("id", decode.int)
  decode.success(#(method, params, token, id))
}
