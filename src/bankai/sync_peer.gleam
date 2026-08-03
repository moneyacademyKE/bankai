//// G6 livesync — bankai-native TCP peer sync of the task store.
////
//// Why not gleamunison/sync? It is distributed-Erlang (connect by Erlang node
//// name) + codebase/definitions-only (it syncs Unison refs, i.e. bankai's
//// mobile RULES, not the task store). Using it for tasks would mean standing
//// up a fragile distributed-Erlang mesh AND misrepresenting tasks as code.
//// See gap_analysis_bankai_vs_beads.md §8B for the investigation.
////
//// bankai's task store is content-addressed, so a pull-based TCP peer sync
//// converges for free: rig A streams its current task set (NDJSON, one task per
//// line); rig B union-merges via sync/merge.gleam. "Live" = a network pull from
//// a RUNNING rig (no git round-trip), deterministic by content-addressing.

import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/types
import gleam/dynamic.{type Dynamic}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/string

pub const default_port = 7654

// FFI — TCP listen/connect (accept/recv_line/send_data/close_s are reused from
// bankai_socket_ffi; they're gen_tcp-generic across UNIX-domain and TCP).
@external(erlang, "bankai_socket_ffi", "listen_tcp")
fn ffi_listen_tcp(port: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "connect_tcp")
fn ffi_connect_tcp(host: String, port: Int) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "accept")
fn ffi_accept(ls: Dynamic) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "recv_line")
fn ffi_recv_line(s: Dynamic) -> Result(String, Dynamic)

@external(erlang, "bankai_socket_ffi", "send_data")
fn ffi_send(s: Dynamic, data: String) -> Result(Dynamic, Dynamic)

@external(erlang, "bankai_socket_ffi", "close_s")
fn ffi_close(s: Dynamic) -> Nil

/// The value after the first `--port`, or `default`. (Shared by sync-serve and
/// sync-pull — lives here so the root main and cli both reach it.)
pub fn parse_port(args: List(String), default: Int) -> Int {
  case args {
    ["--port", v, ..] ->
      case int.parse(v) {
        Ok(n) -> n
        Error(Nil) -> default
      }
    [_, ..rest] -> parse_port(rest, default)
    [] -> default
  }
}

/// Run the sync server: listen on `port`; for each connecting peer stream the
/// current task set (NDJSON), then close. Blocks (run via `bankai sync-serve`).
pub fn serve(workspace: String, port: Int) -> Nil {
  let tasks_path = workspace <> "/tasks.jsonl"
  case ffi_listen_tcp(port) {
    Error(_) ->
      io.println_error(
        "bankai sync-serve: failed to listen on port " <> int.to_string(port),
      )
    Ok(ls) -> {
      io.println(
        "bankai sync-serve listening on port "
        <> int.to_string(port)
        <> " (pull-based task sync)",
      )
      serve_loop(tasks_path, ls)
    }
  }
}

fn serve_loop(tasks_path: String, ls: Dynamic) -> Nil {
  case ffi_accept(ls) {
    Error(_) -> Nil
    Ok(conn) -> {
      handle_pull(tasks_path, conn)
      serve_loop(tasks_path, ls)
    }
  }
}

fn handle_pull(tasks_path: String, conn: Dynamic) -> Nil {
  // Stream the current task set — one JSON task per line. The current view is
  // sufficient for operational convergence (content-addressed union-merge on
  // the peer collapses to the latest per id).
  let tasks = store.current_tasks(load_store(tasks_path))
  list.each(tasks, fn(t) {
    let _ = ffi_send(conn, serde.task_to_json_string(t) <> "\n")
  })
  let _ = ffi_close(conn)
  Nil
}

/// Connect to a peer's sync server, read its task set, union-merge into the
/// local store. Returns the count of tasks pulled (pre-merge).
pub fn pull(workspace: String, host: String, port: Int) -> Result(Int, String) {
  let tasks_path = workspace <> "/tasks.jsonl"
  case ffi_connect_tcp(host, port) {
    Error(_) ->
      Error(
        "could not connect to sync peer at "
        <> host
        <> ":"
        <> int.to_string(port),
      )
    Ok(conn) -> {
      let remote = read_tasks(conn, [])
      let _ = ffi_close(conn)
      let local = store.list(load_store(tasks_path))
      let merged = merge.merge(local, remote)
      let _ = jsonl.flush(merged.tasks, to: tasks_path)
      Ok(list.length(remote))
    }
  }
}

fn read_tasks(conn: Dynamic, acc: List(types.Task)) -> List(types.Task) {
  case ffi_recv_line(conn) {
    // EOF / peer closed the stream after sending its set.
    Error(_) -> list.reverse(acc)
    Ok(line) ->
      case json.parse(from: string.trim(line), using: serde.task_decoder()) {
        Ok(t) -> read_tasks(conn, [t, ..acc])
        Error(_) -> read_tasks(conn, acc)
      }
  }
}

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}
