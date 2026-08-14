//// Regression tests for bk-cb86: argv codepoints above 255 must become
//// UTF-8 binaries, not crash the CLI with badarg.

import gleeunit/should

@external(erlang, "bankai_argv_ffi", "to_utf8")
fn to_utf8(chars: List(Int)) -> BitArray

pub fn ascii_passes_through_test() {
  to_utf8([104, 101, 108, 108, 111])
  |> should.equal(<<"hello":utf8>>)
}

pub fn em_dash_encodes_as_utf8_test() {
  // U+2014 EM DASH (codepoint 8212) crashed list_to_binary before bk-cb86
  to_utf8([8212])
  |> should.equal(<<226, 128, 148>>)
}

pub fn accents_and_cjk_encode_test() {
  to_utf8([99, 97, 102, 233]) |> should.equal(<<"café":utf8>>)
  to_utf8([20_320, 22_909]) |> should.equal(<<"你好":utf8>>)
}
