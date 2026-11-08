//// bk-2d1b: --help/-h/help must answer with usage without booting a
//// daemon, workspace, or MCP server. The routing lives in main(), but
//// the decision it consults is this pure seam, and the usage text it
//// prints is pinned here. The original defect: `--help` reached the
//// dispatch and got "unknown command", while `serve --help` parked a
//// BEAM node for days.

import bankai/cli
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// Every spelling a user might reach for, in the position main() and
/// the long-running verbs actually check.
pub fn wants_help_recognises_every_spelling_test() {
  [
    ["--help"],
    ["-h"],
    ["help"],
    ["serve-usage", "--help"],
    ["--port", "1", "-h"],
  ]
  |> list.all(cli.wants_help)
  |> should.be_true
}

/// Real argvs that must NOT be hijacked: an ordinary command, a flag
/// the parser owns, an empty call, and task text that merely contains
/// the word in a longer token.
pub fn wants_help_ignores_real_commands_test() {
  [
    [],
    ["create", "help me fix this"],
    ["serve"],
    ["--port", "17999"],
    ["sync-serve", "--port", "17999"],
  ]
  |> list.all(fn(args) { !cli.wants_help(args) })
  |> should.be_true
}

/// The usage text documents the help spellings and the blocking verbs,
/// so `bankai --help` advertises the contract it just honoured.
pub fn usage_documents_help_and_servers_test() {
  let text = cli.usage()
  text |> string.contains("--help, -h, help") |> should.be_true
  text |> string.contains("serve") |> should.be_true
  text |> string.contains("mcp") |> should.be_true
}
