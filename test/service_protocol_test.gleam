//// bk-a5a4: the authenticated wire protocol must share socket_wire's
//// UTF-8-safe trim and response envelopes.

import bankai/service_protocol
import gleam/string
import gleeunit
import gleeunit/should

@external(erlang, "bankai_wire_ffi", "partial_line")
fn wire_partial_line() -> String

pub fn main() {
  gleeunit.main()
}

fn dispatch(_method: String, _params: List(String)) -> Result(String, String) {
  Error("dispatch should not run in these protocol-guard tests")
}

/// A split multi-byte codepoint must become an ordinary parse error rather
/// than crashing string.trim inside the daemon handler.
pub fn handle_line_truncated_utf8_test() {
  service_protocol.handle_line(
    "/tmp/bankai_service_protocol_utf8",
    wire_partial_line(),
    dispatch,
  )
  |> string.contains("parse error")
  |> should.be_true
}

/// Valid multibyte JSON reaches the credential gate, proving the guard rejects
/// invalid UTF-8 rather than all non-ASCII text.
pub fn handle_line_valid_multibyte_parses_test() {
  let line = "{\"method\":\"list\",\"params\":[\"bk-a5a4 — guard\"],\"id\":7}"
  service_protocol.handle_line(
    "/tmp/bankai_service_protocol_utf8",
    line,
    dispatch,
  )
  |> string.contains("missing capability token")
  |> should.be_true
}
