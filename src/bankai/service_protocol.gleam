//// Authenticated JSON-line protocol for the resident Bankai service.
////
//// This module owns credential decoding and the authorization gate. The
//// supplied dispatch function receives only method/params data after authority
//// has been established, so domain handlers remain credential-free.

import bankai/service_auth
import gleam/dynamic/decode
import gleam/json
import gleam/string

pub fn handle_line(
  workspace: String,
  line: String,
  dispatch: fn(String, List(String)) -> Result(String, String),
) -> String {
  case parse_request(line) {
    Error(_) -> error_response("parse error", 0)
    Ok(#(method, params, token, id)) ->
      case token {
        "" -> error_response("missing capability token", id)
        _ ->
          case
            service_auth.authorize_request(workspace, token, method, params)
          {
            Error(message) -> error_response(message, id)
            Ok(Nil) ->
              case dispatch(method, params) {
                Ok(value) -> ok_response(value, id)
                Error(message) -> error_response(message, id)
              }
          }
      }
  }
}

fn parse_request(
  line: String,
) -> Result(#(String, List(String), String, Int), Nil) {
  case json.parse(from: string.trim(line), using: request_decoder()) {
    Ok(request) -> Ok(request)
    Error(_) -> Error(Nil)
  }
}

fn request_decoder() -> decode.Decoder(#(String, List(String), String, Int)) {
  use method <- decode.field("method", decode.string)
  use params <- decode.field("params", decode.list(of: decode.string))
  use token <- decode.optional_field("token", "", decode.string)
  use id <- decode.field("id", decode.int)
  decode.success(#(method, params, token, id))
}

fn ok_response(value: String, id: Int) -> String {
  json.object([#("result", json.string(value)), #("id", json.int(id))])
  |> json.to_string
}

fn error_response(message: String, id: Int) -> String {
  json.object([#("error", json.string(message)), #("id", json.int(id))])
  |> json.to_string
}
