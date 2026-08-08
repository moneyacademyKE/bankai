//// G11 — MCP server protocol tests (handle_message is pure; stdio is the FFI).

import bankai/cli
import bankai/mcp
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn wipe(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = simplifile.write("", to: ws <> "/archive.jsonl")
  Nil
}

const ws = "/tmp/bankai_mcp_test"

pub fn initialize_responds_with_capabilities_test() {
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\"}",
    )
  resp |> string.contains("\"protocolVersion\"") |> should.be_true
  resp |> string.contains("\"tools\"") |> should.be_true
  resp |> string.contains("\"id\":1") |> should.be_true
  resp |> string.contains("\"version\":\"0.2.0\"") |> should.be_true
}

pub fn tools_list_advertises_bankai_commands_test() {
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    )
  resp |> string.contains("ready") |> should.be_true
  resp |> string.contains("create") |> should.be_true
  resp |> string.contains("dep_list") |> should.be_true
  resp |> string.contains("dep_tree") |> should.be_true
  resp |> string.contains("doctor") |> should.be_true
}

pub fn tools_call_reports_daemon_requirement_without_jsonl_fallback_test() {
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"create\",\"arguments\":{\"args\":[\"Must not write JSONL\"]}}}",
    )
  resp |> string.contains("\"content\"") |> should.be_true
  resp |> string.contains("\"isError\":true") |> should.be_true
  resp |> string.contains("daemon required") |> should.be_true
  cli.run_in(ws, ["list"])
  |> string.contains("Must not write JSONL")
  |> should.be_false
}

pub fn initialized_notification_emits_no_response_test() {
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    )
  resp |> should.equal("")
}

pub fn unknown_method_is_a_jsonrpc_error_test() {
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"frobnicate\"}",
    )
  resp |> string.contains("method not found") |> should.be_true
  resp |> string.contains("\"id\":4") |> should.be_true
}
