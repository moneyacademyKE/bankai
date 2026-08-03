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
}

pub fn tools_list_advertises_bankai_commands_test() {
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
    )
  resp |> string.contains("ready") |> should.be_true
  resp |> string.contains("create") |> should.be_true
  resp |> string.contains("dep_add") |> should.be_true
  resp |> string.contains("compact") |> should.be_true
}

pub fn tools_call_routes_to_bankai_and_returns_content_test() {
  wipe(ws)
  let _ = cli.run_in(ws, ["init"])
  let _ = cli.run_in(ws, ["create", "Callable task"])
  let resp =
    mcp.handle_message(
      ws,
      "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/call\",\"params\":{\"name\":\"list\",\"arguments\":{\"args\":[]}}}",
    )
  resp |> string.contains("\"content\"") |> should.be_true
  resp |> string.contains("Callable task") |> should.be_true
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
