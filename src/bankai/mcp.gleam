//// G11 — MCP (Model Context Protocol) stdio server. It shares Bankai's daemon
//// boundary for task operations; it never invokes JSONL-backed task handlers.
////
//// Transport: newline-delimited JSON-RPC over stdio (the MCP spec's only stdio
//// framing — "Messages are delimited by newlines, and MUST NOT contain embedded
//// newlines"). Each tools/call wraps the daemon's existing {"ok"}/{"error"}
//// envelope as MCP text content.
////
//// This is the Hickey-compatible "compose don't build" path: mcp_toolkit exists
//// on Hex but hard-depends on Mist (the web-framework weight aarondb was dropped
//// for), so the stdio path reuses Bankai's daemon protocol instead.

import bankai/socket
import bankai/version
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

/// Run the MCP stdio server against a workspace. Blocks reading stdin until EOF.
pub fn serve(workspace: String) -> Nil {
  loop(workspace)
}

fn loop(workspace: String) -> Nil {
  case read_line() {
    Error(Nil) -> Nil
    Ok(line) -> {
      // stdout is reserved for protocol messages ONLY — anything else would
      // corrupt the client's NDJSON parser. (Notifications get no response.)
      case handle_message(workspace, string.trim(line)) {
        "" -> Nil
        response -> io.println(response)
      }
      loop(workspace)
    }
  }
}

/// Pure dispatch over one JSON-RPC message line — pub so the protocol layer is
/// testable without stdio. Returns "" when no response is owed (notification).
pub fn handle_message(workspace: String, line: String) -> String {
  case method_and_id(line) {
    Error(Nil) -> ""
    Ok(#(method, id_opt)) ->
      case method, id_opt {
        "initialize", option.Some(id) -> ok_response(id, initialize_result())
        "ping", option.Some(id) -> ok_response(id, json.object([]))
        "tools/list", option.Some(id) -> ok_response(id, tools_list_result())
        "tools/call", option.Some(id) ->
          ok_response(id, tools_call(workspace, line))
        "notifications/initialized", _ -> ""
        _, option.Some(id) ->
          error_response(id, -32_601, "method not found: " <> method)
        _, option.None -> ""
      }
  }
}

// --- MCP method handlers ---

fn initialize_result() -> json.Json {
  json.object([
    #("protocolVersion", json.string("2025-11-25")),
    #("capabilities", json.object([#("tools", json.object([]))])),
    #(
      "serverInfo",
      json.object([
        #("name", json.string("bankai")),
        #("version", json.string(version.current)),
      ]),
    ),
  ])
}

fn tools_list_result() -> json.Json {
  json.object([#("tools", json.array(tools(), of: fn(t) { t }))])
}

fn tools_call(workspace: String, line: String) -> json.Json {
  let #(name, args) = parse_call(line)
  let #(method, params) = daemon_request(name, args)
  let envelope = case socket.client_request(workspace, method, params) {
    Ok(value) -> value
    Error(_) -> daemon_required_envelope(name)
  }
  let is_error = string.starts_with(envelope, "{\"error\"")
  json.object([
    #("content", json.array([text_content(envelope)], of: fn(j) { j })),
    #("isError", json.bool(is_error)),
  ])
}

fn daemon_request(name: String, args: List(String)) -> #(String, List(String)) {
  case name {
    "gate_satisfy" -> #("update", [id_from_args(args), "--satisfy-gate"])
    "wisp_create" -> #("create", args_with_kind(args))
    "dep_add" -> #("dep_add", args)
    "dep_list" -> #("dep_list", args)
    "dep_tree" -> #("dep_tree", args)
    "doctor" -> #("doctor", args)
    other -> #(other, args)
  }
}

fn id_from_args(args: List(String)) -> String {
  case args {
    [id, ..] -> id
    [] -> ""
  }
}

fn args_with_kind(args: List(String)) -> List(String) {
  list.append(args, ["--kind", "wisp"])
}

fn daemon_required_envelope(name: String) -> String {
  case is_task_operation(name) {
    True ->
      "{\"error\":\"bankai daemon required for task operations; run bankai serve\"}"
    False ->
      "{\"error\":\"MCP tool is unavailable without a daemon: " <> name <> "\"}"
  }
}

fn is_task_operation(name: String) -> Bool {
  case name {
    "ready"
    | "list"
    | "show"
    | "create"
    | "update"
    | "dep_add"
    | "dep_list"
    | "dep_tree"
    | "doctor"
    | "merge"
    | "inspect"
    | "gate_satisfy"
    | "wisp_create"
    | "remember"
    | "memories"
    | "compact" -> True
    _ -> False
  }
}

// --- tool catalog ---

fn tools() -> List(json.Json) {
  [
    tool(
      "ready",
      "List unblocked tasks, or atomically claim one. args: [\"--label\", \"L\"] | [\"--claim\", \"assignee\", \"--label\", \"L\"].",
    ),
    tool("list", "List all current tasks. Optional: args [\"--label\", \"L\"]."),
    tool("show", "Show a task by id. args: [\"bk-xxxx\"]."),
    tool("create", "Create a task. args: [\"title\", \"--label\", \"L\"...]."),
    tool(
      "update",
      "Update a task. args: [\"bk-xxxx\", \"completed\"] | [\"bk-xxxx\", \"--claim\"] | [\"bk-xxxx\", \"--label\", \"L\"].",
    ),
    tool(
      "dep_list",
      "List typed dependency edges for a task. args: [\"bk-task\"].",
    ),
    tool(
      "dep_tree",
      "Return a cycle-safe dependency tree for a task. args: [\"bk-task\"].",
    ),
    tool("doctor", "Run read-only task-store integrity diagnostics. args: []."),
    tool(
      "merge",
      "Consolidate a reviewed duplicate into a canonical task. args: [\"duplicate-id\", \"canonical-id\"].",
    ),
    tool("remember", "Persist a durable insight. args: [\"insight text\"]."),
    tool("memories", "List persisted memories."),
    tool("inspect", "Inspect a task by content hash. args: [\"<hex>\"]."),
    tool("compact", "Retire closed tasks into the archive."),
    tool("gate_satisfy", "Satisfy a manual gate. args: [\"gate-id\"]."),
    tool("wisp_create", "Create a local-only wisp. args: [\"title\"]."),
  ]
}

fn tool(name: String, description: String) -> json.Json {
  json.object([
    #("name", json.string(name)),
    #("description", json.string(description)),
    #(
      "inputSchema",
      json.object([
        #("type", json.string("object")),
        #(
          "properties",
          json.object([
            #(
              "args",
              json.object([
                #("type", json.string("array")),
                #("items", json.object([#("type", json.string("string"))])),
              ]),
            ),
          ]),
        ),
        #("required", json.array([], of: fn(j) { j })),
      ]),
    ),
  ])
}

fn text_content(text: String) -> json.Json {
  json.object([
    #("type", json.string("text")),
    #("text", json.string(text)),
  ])
}

// --- JSON-RPC framing ---

fn ok_response(id: Int, result: json.Json) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(id)),
      #("result", result),
    ]),
  )
}

fn error_response(id: Int, code: Int, message: String) -> String {
  json.to_string(
    json.object([
      #("jsonrpc", json.string("2.0")),
      #("id", json.int(id)),
      #(
        "error",
        json.object([
          #("code", json.int(code)),
          #("message", json.string(message)),
        ]),
      ),
    ]),
  )
}

// --- parsing ---

/// method + optional id. A request has an id; a notification does not. We use a
/// sentinel (-1) for an absent id — real JSON-RPC ids are non-negative here.
fn request_decoder() -> decode.Decoder(#(String, Option(Int))) {
  use method <- decode.field("method", decode.string)
  use id_raw <- decode.optional_field("id", -1, decode.int)
  let id_opt = case id_raw {
    -1 -> option.None
    n -> option.Some(n)
  }
  decode.success(#(method, id_opt))
}

fn method_and_id(line: String) -> Result(#(String, Option(Int)), Nil) {
  case json.parse(from: line, using: request_decoder()) {
    Ok(r) -> Ok(r)
    Error(_) -> Error(Nil)
  }
}

fn parse_call(line: String) -> #(String, List(String)) {
  let name = case
    json.parse(from: line, using: decode.at(["params", "name"], decode.string))
  {
    Ok(n) -> n
    Error(_) -> ""
  }
  let args = case
    json.parse(
      from: line,
      using: decode.at(
        ["params", "arguments", "args"],
        decode.list(of: decode.string),
      ),
    )
  {
    Ok(a) -> a
    Error(_) -> []
  }
  #(name, args)
}

@external(erlang, "bankai_stdin_ffi", "read_line")
fn read_line() -> Result(String, Nil)
