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
