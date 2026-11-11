//// bk-4d82: the wire layer must survive truncated UTF-8.
////
//// gen_tcp {packet, line} chunks can split a multi-byte codepoint at the
//// recv-buffer boundary, and recv_full_response feeds every partial
//// accumulation to extract_result as its completeness check. One split
//// em-dash used to raise badarg inside string:trim and kill the whole
//// `list` verb; now an invalid line is an Error the accumulation loop
//// already knows how to handle.

import bankai/socket_wire
import gleam/string
import gleeunit
import gleeunit/should

@external(erlang, "bankai_wire_ffi", "partial_line")
fn wire_partial_line() -> String

@external(erlang, "bankai_wire_ffi", "completed_line")
fn wire_completed_line() -> String

pub fn main() {
  gleeunit.main()
}

/// A chunk boundary split the trailing codepoint: the completeness check
/// must say "not a parseable response" (Error), never crash.
pub fn extract_result_truncated_utf8_test() {
  should.equal(
    socket_wire.extract_result(wire_partial_line()),
    Error("daemon response contained invalid UTF-8"),
  )
}

/// The same line with the codepoint completed parses normally: accumulation
/// converging on the full response is the happy path this guard protects.
pub fn extract_result_completed_multibyte_line_test() {
  let assert Ok(text) = socket_wire.extract_result(wire_completed_line())
  should.be_true(string.contains(text, "gates as filed"))
}

/// The request parser has the same badarg class: a truncated multi-byte chunk
/// must return an ordinary parse error, never crash the daemon handler.
pub fn parse_request_truncated_utf8_test() {
  socket_wire.parse_request(wire_partial_line()) |> should.equal(Error(Nil))
}

/// Valid multibyte JSON still parses: the guard rejects invalid UTF-8, not
/// non-ASCII text.
pub fn parse_request_valid_multibyte_test() {
  let line = "{\"method\":\"list\",\"params\":[\"bk-eb25 — guard\"],\"id\":1}"
  socket_wire.parse_request(line)
  |> should.equal(Ok(#("list", ["bk-eb25 — guard"], 1)))
}

/// A truncated codepoint is a syntactic decode failure, distinct from a
/// malformed but valid-UTF-8 envelope.
pub fn parse_response_truncated_utf8_test() {
  socket_wire.parse_response(wire_partial_line())
  |> should.equal(Error("daemon response contained invalid UTF-8"))
}

/// A complete application error is syntactically whole. parse_response must
/// succeed so recv_full_response stops accumulating; extract_result then
/// interprets the envelope's error field.
pub fn parse_response_complete_error_test() {
  let line = "{\"error\":\"boom\",\"id\":1}"
  socket_wire.parse_response(line) |> should.equal(Ok(#("", "boom")))
  socket_wire.extract_result(line) |> should.equal(Error("boom"))
}

/// Invalid JSON is a malformed response, not an application error.
pub fn parse_response_malformed_test() {
  socket_wire.parse_response("{\"result\":}")
  |> should.equal(Error("malformed daemon response"))
}
