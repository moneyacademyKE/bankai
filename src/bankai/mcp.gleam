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

// --- tool catalog ---

fn tools() -> List(json.Json) {
  [
    tool(
      "ready",
      "Query readiness or explanations with shared filters/sort/page options. Add --explain for data-shaped reasons or --claim to atomically claim.",
    ),
    tool(
      "list",
      "Query current tasks with status/kind/priority/assignee/label/date/sort/page filters; --compact selects a brief projection.",
    ),
    tool("count", "Count tasks matching the same structured query options."),
    tool("blocked", "Query blocked tasks with the same structured options."),
    tool("show", "Show a task by id. args: [\"bk-xxxx\"]."),
    tool("create", "Create a task. args: [\"title\", \"--label\", \"L\"...]."),
    tool(
      "update",
      "Update lifecycle: status, claim, release, reopen, defer/undefer, add/remove label, priority.",
    ),
    tool(
      "batch",
      "Atomically apply one mutation per task. args: [\"--idempotency-key\", \"key\", \"release:bk-a\", \"priority:bk-b:5\"].",
    ),
    tool(
      "dep_list",
      "List typed dependency edges for a task. args: [\"bk-task\"].",
    ),
    tool(
      "dep_remove",
      "Remove one typed edge idempotently. args: [\"bk-task\", \"bk-target\", \"--type\", \"blocks\"].",
    ),
    tool(
      "dep_tree",
      "Return a cycle-safe dependency tree for a task. args: [\"bk-task\"].",
    ),
    tool(
      "dep_traverse",
      "Traverse typed edges. args: [\"bk-task\", \"--direction\", \"incoming|outgoing|both\", \"--type\", \"blocks\", \"--depth\", \"2\"].",
    ),
    tool("dep_graph", "Export stable JSON nodes and typed edges."),
    tool("dep_check", "Check missing targets, cycles, and duplicate edges."),
    tool("doctor", "Run read-only task-store integrity diagnostics. args: []."),
    tool(
      "cluster_status",
      "Report local/cluster mode, transport admission, leader, quorum, ReadIndex, leases, projections, and recovery state. args: [].",
    ),
    tool(
      "platform_status",
      "Alias for cluster_status with transport and recovery diagnostics. args: [].",
    ),
    tool(
      "merge",
      "Consolidate a reviewed duplicate into a canonical task. args: [\"duplicate-id\", \"canonical-id\"].",
    ),
    tool("remember", "Persist a durable insight. args: [\"insight text\"]."),
    tool("memories", "List persisted memories."),
    tool("inspect", "Inspect a task by content hash. args: [\"<hex>\"]."),
    tool("compact", "Retire closed tasks into the archive."),
    tool("backup_list", "List all task backups in workspace. args: []."),
    tool(
      "backup_preview",
      "Preview divergence between backup and current store. args: [\"path\"].",
    ),
    tool(
      "backup_restore",
      "Restore a validated backup into Mnesia. args: [\"path\"].",
    ),
    tool("backup_prune", "Prune old backups. args: [\"--keep\", \"5\"]."),
    tool(
      "sync_conflicts",
      "List recorded replication and federation conflicts. args: [].",
    ),
    tool(
      "sync_conflict_resolve",
      "Resolve and clear a recorded conflict. args: [\"conflict-id\"].",
    ),
    tool(
      "sync_conflict_clear",
      "Clear all recorded replication conflicts. args: [].",
    ),
    tool(
      "journal_tail",
      "Tail committed changefeed journal events. args: [\"--after\", \"0\"].",
    ),
    tool("gate_satisfy", "Resolve a manual gate. args: [\"gate-id\"]."),
    tool(
      "gate_list",
      "List gates deterministically; optional --state all|open|pending.",
    ),
    tool(
      "gate_show",
      "Show gate evaluation, waiters, local escalation data, and audit.",
    ),
    tool(
      "gate_check",
      "Evaluate gate state and waiter readiness without mutation.",
    ),
    tool(
      "gate_resolve",
      "Resolve with optional --dry-run, --actor, and --reason.",
    ),
    tool(
      "gate_fact_ingest",
      "Verify and atomically persist signed external fact data.",
    ),
    tool(
      "wisp_create",
      "Create local-only wisp; optional --ttl seconds or --expires-at.",
    ),
    tool(
      "wisp_list",
      "List wisps deterministically; optional --state all|active|expired.",
    ),
    tool("wisp_promote", "Archive source and promote a wisp to a normal task."),
    tool("wisp_digest", "Derive a non-destructive wisp digest/squash view."),
    tool("wisp_burn", "Archive canonical current head before removing a wisp."),
    tool("wisp_gc", "Deterministically burn expired wisps; supports --dry-run."),
    tool("wisp_archive", "List ordered wisp archive evidence."),
    tool(
      "molecule_register",
      "Register immutable declarative template JSON. args: [\"<json>\"].",
    ),
    tool("molecule_list", "List registered molecule templates."),
    tool("molecule_show", "Show a template. args: [\"<hash>\"]."),
    tool(
      "molecule_instantiate",
      "Atomically instantiate. args: [\"<hash>\",\"--idempotency-key\",\"key\",\"name=value\"...].",
    ),
    tool(
      "molecule_compose",
      "Compose two templates. args: [\"name\",\"left-hash\",\"right-hash\"].",
    ),
    tool("molecule_instance", "Show instance provenance and tasks."),
    tool("molecule_provenance", "Show task-to-template provenance."),
    tool("molecule_progress", "Derive instance progress."),
    tool("molecule_current", "List current ready instance steps."),
    tool("molecule_distill", "Derive a non-destructive instance digest."),
    tool(
      "rule_register",
      "Register an unapproved local rule artifact. args: [\"name\", \"source\"].",
    ),
    tool("rule_list", "List local rule artifacts and approval state."),
    tool("rule_show", "Show a local rule artifact. args: [\"hash\"]."),
    tool("rule_approve", "Approve a local rule hash. args: [\"hash\"]."),
    tool("rule_revoke", "Revoke local rule approval. args: [\"hash\"]."),
    tool(
      "rule_eval",
      "Evaluate an approved rule against an immutable task view. args: [\"hash\", \"--caller\", \"name\", \"--task\", \"task-id\"].",
    ),
    tool(
      "rule_audit",
      "List durable local rule audit records. Optional args: [\"hash\"].",
    ),
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
