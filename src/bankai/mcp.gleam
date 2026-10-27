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

import bankai/mcp_catalog
import bankai/socket
import bankai/version
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import gleamunison/sap.{type Schema, SObj, SText}

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
        "tools/list", option.Some(id) -> ok_response(id, catalog_result())
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

fn catalog_result() -> json.Json {
  json.object([#("tools", json.array(mcp_catalog.tools(), of: fn(t) { t }))])
}

fn tools_call(workspace: String, line: String) -> json.Json {
  let #(name, args) = parse_call(line)
  let envelope = case is_advertised_tool(name) {
    False -> "{\"error\":\"unknown MCP tool: " <> name <> "\"}"
    True -> {
      let #(method, params) = daemon_request(name, args)
      case socket.client_request(workspace, method, params) {
        Ok(value) -> value
        Error(_) -> daemon_required_envelope(name)
      }
    }
  }
  let is_error = string.starts_with(envelope, "{\"error\"")
  json.object([
    #("content", json.array([text_content(envelope)], of: fn(j) { j })),
    #("isError", json.bool(is_error)),
  ])
}

fn text_content(text: String) -> json.Json {
  json.object([
    #("type", json.string("text")),
    #("text", json.string(text)),
  ])
}

fn is_advertised_tool(name: String) -> Bool {
  case name {
    "ready"
    | "list"
    | "count"
    | "blocked"
    | "show"
    | "create"
    | "update"
    | "batch"
    | "dep_list"
    | "dep_tree"
    | "dep_traverse"
    | "dep_graph"
    | "dep_check"
    | "doctor"
    | "cluster_status"
    | "platform_status"
    | "merge"
    | "remember"
    | "memories"
    | "inspect"
    | "compact"
    | "gate_satisfy"
    | "gate_list"
    | "gate_show"
    | "gate_check"
    | "gate_resolve"
    | "gate_fact_ingest"
    | "wisp_create"
    | "wisp_list"
    | "wisp_promote"
    | "wisp_digest"
    | "wisp_burn"
    | "wisp_gc"
    | "wisp_archive"
    | "backup_list"
    | "backup_preview"
    | "backup_restore"
    | "backup_prune"
    | "sync_conflicts"
    | "sync_conflict_resolve"
    | "sync_conflict_clear"
    | "sync_identity"
    | "sync_trust"
    | "sync_revoke"
    | "sync_rotate"
    | "journal_tail"
    | "molecule_register"
    | "molecule_list"
    | "molecule_show"
    | "molecule_instantiate"
    | "molecule_compose"
    | "molecule_instance"
    | "molecule_provenance"
    | "molecule_progress"
    | "molecule_current"
    | "molecule_distill" -> True
    _ -> False
  }
}

fn daemon_request(name: String, args: List(String)) -> #(String, List(String)) {
  case name {
    "gate_satisfy" -> #("gate_resolve", [id_from_args(args)])
    "wisp_create" -> #("create", args_with_kind(args))
    "gate_list" -> #("gate_list", args)
    "gate_show" -> #("gate_show", args)
    "gate_check" -> #("gate_check", args)
    "gate_resolve" -> #("gate_resolve", args)
    "gate_fact_ingest" -> #("gate_fact_ingest", args)
    "wisp_list" -> #("wisp_list", args)
    "wisp_promote" -> #("wisp_promote", args)
    "wisp_digest" -> #("wisp_digest", args)
    "wisp_burn" -> #("wisp_burn", args)
    "wisp_gc" -> #("wisp_gc", args)
    "wisp_archive" -> #("wisp_archive", args)
    "backup_list" -> #("backup_list", args)
    "backup_preview" -> #("backup_preview", args)
    "backup_restore" -> #("backup_restore", args)
    "backup_prune" -> #("backup_prune", args)
    "sync_conflicts" -> #("sync_conflicts", args)
    "sync_conflict_resolve" -> #("sync_conflict_resolve", args)
    "sync_conflict_clear" -> #("sync_conflict_clear", args)
    "sync_identity" -> #("sync_identity", args)
    "sync_trust" -> #("sync_trust", args)
    "sync_revoke" -> #("sync_revoke", args)
    "sync_rotate" -> #("sync_rotate", args)
    "journal_tail" -> #("journal_tail", args)
    "rule_register" -> #("rule_register", args)
    "rule_list" -> #("rule_list", args)
    "rule_show" -> #("rule_show", args)
    "rule_approve" -> #("rule_approve", args)
    "rule_revoke" -> #("rule_revoke", args)
    "rule_eval" -> #("rule_eval", args)
    "rule_audit" -> #("rule_audit", args)
    "dep_add" -> #("dep_add", args)
    "dep_remove" -> #("dep_remove", args)
    "dep_list" -> #("dep_list", args)
    "dep_tree" -> #("dep_tree", args)
    "dep_traverse" -> #("dep_traverse", args)
    "dep_graph" -> #("dep_graph", args)
    "dep_check" -> #("dep_check", args)
    "doctor" -> #("doctor", args)
    "cluster_status" -> #("cluster_status", args)
    "platform_status" -> #("cluster_status", args)
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
    | "batch"
    | "dep_add"
    | "dep_remove"
    | "dep_list"
    | "dep_tree"
    | "dep_traverse"
    | "dep_graph"
    | "dep_check"
    | "doctor"
    | "cluster_status"
    | "platform_status"
    | "merge"
    | "inspect"
    | "gate_satisfy"
    | "gate_list"
    | "gate_show"
    | "gate_check"
    | "gate_resolve"
    | "gate_fact_ingest"
    | "wisp_create"
    | "wisp_list"
    | "wisp_promote"
    | "wisp_digest"
    | "wisp_burn"
    | "wisp_gc"
    | "wisp_archive"
    | "backup_list"
    | "backup_preview"
    | "backup_restore"
    | "backup_prune"
    | "sync_conflicts"
    | "sync_conflict_resolve"
    | "sync_conflict_clear"
    | "sync_identity"
    | "sync_trust"
    | "sync_revoke"
    | "sync_rotate"
    | "journal_tail"
    | "remember"
    | "memories"
    | "compact"
    | "rule_register"
    | "rule_list"
    | "rule_show"
    | "rule_approve"
    | "rule_revoke"
    | "rule_eval"
    | "rule_audit"
    | "molecule_register"
    | "molecule_list"
    | "molecule_show"
    | "molecule_instantiate"
    | "molecule_compose"
    | "molecule_instance"
    | "molecule_provenance"
    | "molecule_progress"
    | "molecule_current"
    | "molecule_distill" -> True
    _ -> False
  }
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
  case json.parse(from: repaired(line), using: request_decoder()) {
    Ok(r) -> Ok(r)
    Error(_) -> Error(Nil)
  }
}

/// MCP lines arrive from models. SAP repairs fences, trailing commas, and
/// single quotes before the strict decoder runs. A line SAP cannot repair
/// is left as-is so a genuinely bad payload still fails loudly.
fn repaired(line: String) -> String {
  case sap.parse(line) {
    Ok(text) -> text
    Error(_) -> line
  }
}

/// Schema for a tools/call. Exposed so the repair contract is testable
/// without standing up stdio.
pub fn call_schema() -> Schema {
  SObj([#("method", SText), #("params", SObj([#("name", SText)], ["name"]))], [
    "method",
  ])
}

pub fn repair_call(line: String) -> Result(String, String) {
  case sap.decode_as(line, call_schema()) {
    Ok(_) ->
      case sap.parse(line) {
        Ok(text) -> Ok(text)
        Error(_) -> Error("sap repaired then lost the span")
      }
    Error(sap.NoJsonFound) -> Error("no json found")
    Error(sap.StrictError(reason)) -> Error(reason)
    Error(sap.ValidationFailed(paths)) -> Error(string.join(paths, ","))
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
