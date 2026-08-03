//// The bankai CLI — single-shot invocation over the JSONL-backed store.
////
//// Each command loads .bankai/tasks.jsonl into the content-addressed store,
//// performs the op, flushes on mutation, and prints JSON. For sub-5ms latency
//// the warm daemon path (bankai/socket) keeps the store resident; this
//// single-shot path trades cold-start cost for zero-daemon simplicity.
////
//// `run_in(workspace, argv)` is pure + testable; `main()` wires system argv.

import bankai/builder
import bankai/graph
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/time
import bankai/types.{type Task, Open}
import gleam/int
import gleam/json
import gleam/list
import gleam/option

pub const default_workspace = ".bankai"

/// Run a command against a workspace, returning the output (JSON or text).
pub fn run_in(workspace: String, argv: List(String)) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  case argv {
    [] -> usage()
    ["init", ..] -> init_cmd(workspace)
    ["create", title, ..] -> create_cmd(workspace, tasks_path, title)
    ["list", ..] -> list_cmd(tasks_path)
    ["ready", ..] -> ready_cmd(tasks_path)
    ["update", id, status, ..] -> update_cmd(tasks_path, id, status)
    ["inspect", hash, ..] -> inspect_cmd(tasks_path, hash)
    ["prime", ..] -> prime_text()
    ["sync", ..] -> sync_cmd(tasks_path)
    [cmd, ..] -> "unknown command: " <> cmd <> "\n\n" <> usage()
  }
}

// --- commands ---

fn init_cmd(workspace: String) -> String {
  let _ = jsonl.ensure_dir(workspace)
  "initialized bankai workspace at " <> workspace
}

fn create_cmd(workspace: String, tasks_path: String, title: String) -> String {
  let _ = jsonl.ensure_dir(workspace)
  let now = time.now()
  let id = "bk-" <> int.to_string(now)
  let task = builder.build(id, title, "", Open, option.None, 1, now, now, [])
  let index = store.put(load_store(tasks_path), task)
  let _ = jsonl.flush(store.list(index), to: tasks_path)
  serde.task_to_json_string(task)
}

fn list_cmd(tasks_path: String) -> String {
  load_store(tasks_path)
  |> store.current_tasks()
  |> tasks_to_json_array()
}

fn ready_cmd(tasks_path: String) -> String {
  load_store(tasks_path)
  |> store.current_tasks()
  |> graph.ready_tasks()
  |> tasks_to_json_array()
}

fn update_cmd(tasks_path: String, id: String, status: String) -> String {
  case serde.status_from_string(status) {
    Ok(new_status) -> {
      // BUG-01 fix: load the store ONCE and thread it through. The previous
      // code reloaded from disk between find_by_id and store.put, so a
      // concurrent write (or any task created in between) was silently
      // discarded on flush. One load, one put, one flush — same store.
      let index = load_store(tasks_path)
      case store.find_by_id(index, id) {
        Ok(task) -> {
          let updated =
            builder.update(task, fn(t) {
              types.Task(..t, status: new_status, updated_at: time.now())
            })
          let index = store.put(index, updated)
          let _ = jsonl.flush(store.list(index), to: tasks_path)
          serde.task_to_json_string(updated)
        }
        Error(Nil) -> "no such task: " <> id
      }
    }
    Error(Nil) -> "invalid status: " <> status
  }
}

fn inspect_cmd(tasks_path: String, hash: String) -> String {
  case store.get_by_hex(load_store(tasks_path), hash) {
    Ok(task) -> serde.task_to_json_string(task)
    Error(Nil) -> "no task for hash: " <> hash
  }
}

fn sync_cmd(tasks_path: String) -> String {
  // Reload + dedupe by content hash + normalize back to disk.
  let tasks = store.list(load_store(tasks_path))
  let _ = jsonl.flush(tasks, to: tasks_path)
  "synced " <> int.to_string(list.length(tasks)) <> " task(s)"
}

// --- helpers ---

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}

fn tasks_to_json_array(tasks: List(Task)) -> String {
  tasks
  |> json.array(of: serde.task_to_json)
  |> json.to_string()
}

pub fn usage() -> String {
  "bankai — content-addressed task memory\n\n"
  <> "usage: bankai <command> [args]\n\n"
  <> "  init                  initialize .bankai/\n"
  <> "  create <title>        create a task, print its JSON\n"
  <> "  list                  list all tasks (JSON array)\n"
  <> "  ready                 list unblocked tasks (JSON array)\n"
  <> "  update <id> <status>  set status (open|in_progress|blocked|completed|closed)\n"
  <> "  inspect <hash>        render the task for a content hash\n"
  <> "  prime                 emit agent-injection prompt\n"
  <> "  sync                  reconcile + flush .bankai/tasks.jsonl\n"
  <> "  serve                 run the daemon (warm JSON-RPC socket path)"
}

pub fn prime_text() -> String {
  "You are an agent operating against the bankai task-memory mesh.\n"
  <> "Task identity is content-addressed (SHA-256 over canonical state).\n"
  <> "Before starting work: run `bankai ready`, claim an unblocked task,\n"
  <> "then `bankai update <id> in_progress`. On completion run\n"
  <> "`bankai update <id> completed`. Use `bankai inspect <hash>` to audit\n"
  <> "any task state cryptographically. Mobile validation rules may be\n"
  <> "registered and executed by content hash (allow-list-gated)."
}
/// `main()` and argv() live in the root module `bankai` (it imports both `cli`
/// and `socket`; importing `socket` here would form a forbidden import cycle).
/// This module exposes the pure, testable `run_in`/`usage`/`prime_text` surface.
