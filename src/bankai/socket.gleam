//// The daemon transport + protocol layer. A resident daemon owns the Mnesia
//// write authority; JSONL is no longer a fallback for mutations.

import bankai/cli
import bankai/cluster_transport
import bankai/daemon_store
import bankai/platform_profile
import bankai/sync/jsonl
import gleam/dynamic.{type Dynamic}
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/int
import gleam/io
import gleam/json
import gleam/result
import gleam/string

pub type Request {
  Request(method: String, params: List(String))
}

pub type Response {
  OkResponse(value: String)
  ErrorResponse(message: String)
}

const socket_filename = "bankai.sock"

pub fn socket_path(workspace: String) -> String {
  workspace <> "/" <> socket_filename
}

// ---------------------------------------------------------------------------
// Public protocol entry point (pure, tested) — dispatches to the CLI ops.
// ---------------------------------------------------------------------------

pub fn handle_request(workspace: String, request: Request) -> Response {
  case request.method {
    "ready" ->
      case request.params {
        ["--claim", ..rest] ->
          daemon_result(daemon_store.claim_next_ready(workspace, rest))
        _ -> daemon_result(daemon_store.ready_tasks(workspace, request.params))
      }

    "list" -> daemon_result(daemon_store.list_tasks(workspace, request.params))
    "create" ->
      case request.params {
        [title, ..rest] ->
          daemon_result(daemon_store.create(workspace, title, rest))
        _ -> ErrorResponse(message: "create requires a title")
      }
    "update" ->
      case request.params {
        [id, "--fence", fence, status, ..] ->
          daemon_result(daemon_store.update_fenced(workspace, id, status, fence))
        [id, status, "--fence", fence, ..] ->
          daemon_result(daemon_store.update_fenced(workspace, id, status, fence))
        [id, "--defer-until", until, ..] ->
          daemon_result(daemon_store.defer_until(workspace, id, until))
        [id, "--satisfy-gate", ..] ->
          daemon_result(daemon_store.satisfy_gate(workspace, id))
        [id, "--close", reason, ..] ->
          daemon_result(daemon_store.close(workspace, id, reason))
        [id, "--claim", ..rest] ->
          daemon_result(daemon_store.claim(workspace, id, rest))
        [id, "--label", label, ..] ->
          daemon_result(daemon_store.add_label(workspace, id, label))
        [id, "--priority", value, ..] ->
          daemon_result(daemon_store.set_priority(workspace, id, value))
        [id, status, ..] ->
          daemon_result(daemon_store.update(workspace, id, status))
        _ ->
          ErrorResponse(
            message: "update requires <id> <status> or --claim [assignee]",
          )
      }
    "merge" ->
      case request.params {
        [source_id, canonical_id, ..] ->
          daemon_result(daemon_store.merge_duplicate(
            workspace,
            source_id,
            canonical_id,
          ))
        _ -> ErrorResponse(message: "merge requires <source-id> <canonical-id>")
      }
    "dep_add" ->
      case request.params {
        [task_id, target_id, ..rest] ->
          daemon_result(daemon_store.add_dependency(
            workspace,
            task_id,
            target_id,
            rest,
          ))
        _ -> ErrorResponse(message: "dep_add requires <task-id> <target-id>")
      }
    "dep_list" ->
      case request.params {
        [id, ..] -> daemon_result(daemon_store.dependency_list(workspace, id))
        _ -> ErrorResponse(message: "dep_list requires <task-id>")
      }
    "dep_tree" ->
      case request.params {
        [id, ..] -> daemon_result(daemon_store.dependency_tree(workspace, id))
        _ -> ErrorResponse(message: "dep_tree requires <task-id>")
      }
    "doctor" -> daemon_result(daemon_store.doctor(workspace))
    "cluster_status" -> daemon_result(daemon_store.cluster_status(workspace))
    "backup" -> daemon_result(daemon_store.backup_jsonl(workspace))
    "export" -> daemon_result(daemon_store.export_jsonl(workspace))
    "import" ->
      case request.params {
        [path, ..] -> daemon_result(daemon_store.import_jsonl(workspace, path))
        _ -> ErrorResponse(message: "import requires <path>")
      }
    "sync_pull" ->
      case request.params {
        ["--host", host, "--port", port_text, ..] ->
          case int.parse(port_text) {
            Ok(port) ->
              daemon_result(daemon_store.pull_peer(workspace, host, port))
            Error(_) ->
              ErrorResponse(message: "sync_pull port must be an integer")
          }
        ["--host", host, ..] ->
          daemon_result(daemon_store.pull_peer(workspace, host, 7654))
        _ ->
          ErrorResponse(
            message: "sync_pull requires --host <host> [--port <n>]",
          )
      }
    "remember" ->
      case request.params {
        [text, ..] -> daemon_result(daemon_store.remember(workspace, text))
        _ -> ErrorResponse(message: "remember requires an insight")
      }
    "memories" -> daemon_result(daemon_store.memories(workspace))
    "compact" -> daemon_result(daemon_store.compact(workspace))
    "show" ->
      case request.params {
        [id, ..] -> daemon_result(daemon_store.show_task(workspace, id))
        _ -> ErrorResponse(message: "show requires <id>")
      }
    "count" ->
      daemon_result(daemon_store.count_tasks(workspace, request.params))
    "blocked" ->
      daemon_result(daemon_store.blocked_tasks(workspace, request.params))
    "cycles" -> daemon_result(daemon_store.cycle_edges(workspace))
    "duplicates" ->
      case request.params {
        ["--semantic", ..rest] ->
          daemon_result(daemon_store.semantic_duplicates(workspace, rest))
        _ -> daemon_result(daemon_store.duplicate_pairs(workspace))
      }
    "stale" ->
      daemon_result(daemon_store.stale_tasks(workspace, request.params))
    "history" ->
      case request.params {
        [id, ..] -> daemon_result(daemon_store.history(workspace, id))
        _ -> ErrorResponse(message: "history requires <id>")
      }
    "analytics" -> daemon_result(daemon_store.analytics(workspace))
    "search" -> daemon_result(daemon_store.search(workspace, request.params))
    "prime_query" ->
      case request.params {
        [query, ..] -> daemon_result(daemon_store.prime_query(workspace, query))
        _ -> ErrorResponse(message: "prime_query requires <query>")
      }
    "epic" ->
      case request.params {
        [id, ..] -> daemon_result(daemon_store.epic(workspace, id))
        _ -> ErrorResponse(message: "epic requires <id>")
      }
    "inspect" ->
      case request.params {
        [hash, ..] -> daemon_result(daemon_store.inspect(workspace, hash))
        _ -> ErrorResponse(message: "inspect requires <hash>")
      }
    "sync" ->
      case request.params {
        ["--from", path, ..] ->
          daemon_result(daemon_store.reconcile_jsonl(workspace, path))
        _ -> ErrorResponse(message: "sync requires --from <path>")
      }
    "init" ->
      case daemon_store.boot(workspace) {
        Ok(_) -> OkResponse(value: cli.run_in(workspace, ["init"]))
        Error(message) -> ErrorResponse(message: message)
      }
    _ -> ErrorResponse(message: "unknown method: " <> request.method)
  }
}

fn daemon_result(result: Result(json.Json, String)) -> Response {
  case result {
    Ok(value) ->
      OkResponse(value: json.to_string(json.object([#("ok", value)])))
    Error(message) -> ErrorResponse(message: message)
  }
}

// ---------------------------------------------------------------------------
// Wire layer: parse a JSON-RPC line, dispatch, emit a JSON-RPC response line.
// ---------------------------------------------------------------------------

/// Handle one raw request line -> one response line (JSON).
pub fn handle_line(workspace: String, line: String) -> String {
  case parse_request(line) {
    Error(_) -> error_response("parse error", 0)
    Ok(#(method, params, id)) -> {
      let resp = handle_request(workspace, Request(method:, params:))
      case resp {
        OkResponse(value) -> ok_response(value, id)
        ErrorResponse(message) -> error_response(message, id)
      }
    }
  }
}

fn parse_request(line: String) -> Result(#(String, List(String), Int), Nil) {
  case json.parse(from: string.trim(line), using: request_decoder()) {
    Ok(req) -> Ok(req)
    Error(_) -> Error(Nil)
  }
}

fn request_decoder() -> decode.Decoder(#(String, List(String), Int)) {
  use method <- decode.field("method", decode.string)
  use params <- decode.field("params", decode.list(of: decode.string))
  use id <- decode.field("id", decode.int)
  decode.success(#(method, params, id))
}

fn ok_response(value: String, id: Int) -> String {
  json.object([#("result", json.string(value)), #("id", json.int(id))])
  |> json.to_string()
}

fn error_response(message: String, id: Int) -> String {
  json.object([#("error", json.string(message)), #("id", json.int(id))])
  |> json.to_string()
}

fn extract_result(line: String) -> Result(String, String) {
  case json.parse(from: string.trim(line), using: response_decoder()) {
    Ok(#(result, error)) ->
      case error == "" {
        True -> Ok(result)
        False -> Error(error)
      }
    Error(_) -> Error("malformed daemon response")
  }
}

fn response_decoder() -> decode.Decoder(#(String, String)) {
  use result <- decode.optional_field("result", "", decode.string)
  use error <- decode.optional_field("error", "", decode.string)
  decode.success(#(result, error))
}

// ---------------------------------------------------------------------------
// Transport (FFI): gen_tcp over a UNIX-domain socket.
// ---------------------------------------------------------------------------

@external(erlang, "bankai_socket_ffi", "listen")
fn ffi_listen(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "accept")
fn ffi_accept(ls: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "recv_line")
fn ffi_recv_line(sock: Dynamic) -> Result(String, Dynamic)

@external(erlang, "bankai_socket_ffi", "send_data")
fn ffi_send(sock: Dynamic, data: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "close_s")
fn ffi_close(sock: Dynamic) -> Nil

@external(erlang, "bankai_socket_ffi", "connect")
fn ffi_connect(path: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "delete_path")
fn ffi_delete_path(path: String) -> Nil

@external(erlang, "bankai_socket_ffi", "controlling_process")
fn ffi_controlling_process(
  sock: Dynamic,
  pid: process.Pid,
) -> Result(Dynamic, Dynamic)

// ---------------------------------------------------------------------------
// Daemon: `bankai serve` — blocks in an accept loop.
// ---------------------------------------------------------------------------

/// Start an explicit local-mode daemon. A clustered profile is refused here so
/// callers cannot accidentally create a second independent writer.
pub fn serve(workspace: String) -> Nil {
  platform_profile.load(workspace)
  |> result.try(platform_profile.require_local_daemon)
  |> serve_with_profile(workspace, "local")
}

/// Start an explicit clustered daemon. The platform profile and TLS-distribution
/// admission config must agree before command admission can materialize Mnesia
/// state. A bad config fails closed rather than emitting local-only cluster lies.
pub fn serve_clustered(workspace: String) -> Nil {
  platform_profile.load(workspace)
  |> result.try(platform_profile.require_clustered_daemon)
  |> result.try(fn(_) {
    platform_profile.load(workspace)
    |> result.try(fn(profile) {
      cluster_transport.require_ready(workspace, profile)
    })
  })
  |> serve_with_profile(workspace, "clustered")
}

fn serve_with_profile(
  profile: Result(Nil, String),
  workspace: String,
  mode: String,
) -> Nil {
  let _ = jsonl.ensure_dir(workspace)
  case profile, daemon_store.boot(workspace) {
    Error(message), _ ->
      io.println_error("bankai: platform profile failed: " <> message)
    _, Error(message) ->
      io.println_error("bankai: Mnesia boot failed: " <> message)
    Ok(_), Ok(_) -> listen(workspace, mode)
  }
}

fn listen(workspace: String, mode: String) -> Nil {
  let path = socket_path(workspace)
  let _ = ffi_delete_path(path)
  case ffi_listen(path) {
    Error(_) -> io.println_error("bankai: failed to listen on " <> path)
    Ok(ls) -> {
      io.println("bankai " <> mode <> " daemon listening on " <> path)
      serve_loop(workspace, ls)
    }
  }
}

fn serve_loop(workspace: String, ls: Dynamic) -> Nil {
  case ffi_accept(ls) {
    Error(_) -> Nil
    Ok(sock) -> {
      // Isolate each connection: a handler crash must not kill the accept loop.
      // BUG-05 fix: hand socket control to the handler so its lifetime + close
      // signals are tied to the handler (else the socket leaks when a handler
      // dies and error signals route to the acceptor).
      let handler = process.spawn(fn() { handle_conn(workspace, sock) })
      let _ = ffi_controlling_process(sock, handler)
      serve_loop(workspace, ls)
    }
  }
}

fn handle_conn(workspace: String, sock: Dynamic) -> Nil {
  case ffi_recv_line(sock) {
    Ok(line) -> {
      let _ = ffi_send(sock, handle_line(workspace, line) <> "\n")
      Nil
    }
    Error(_) -> Nil
  }
  let _ = ffi_close(sock)
  Nil
}

// ---------------------------------------------------------------------------
// Client: connect to a running daemon and send one request.
// ---------------------------------------------------------------------------

/// Send one request to the daemon over the socket if it's up.
/// Returns Error when no daemon is listening (caller falls back to single-shot).
pub fn client_request(
  workspace: String,
  method: String,
  params: List(String),
) -> Result(String, String) {
  case ffi_connect(socket_path(workspace)) {
    Error(_) -> Error("no daemon")
    Ok(sock) -> {
      let req =
        json.object([
          #("method", json.string(method)),
          #("params", json.array(params, of: json.string)),
          #("id", json.int(1)),
        ])
        |> json.to_string()
      let _ = ffi_send(sock, req <> "\n")
      let result = ffi_recv_line(sock)
      let _ = ffi_close(sock)
      case result {
        Ok(line) -> extract_result(line)
        Error(_) -> Error("no response from daemon")
      }
    }
  }
}
