//// The bankai CLI — single-shot invocation over the JSONL-backed store.
////
//// Every command result is wrapped in a JSON envelope: {"ok": <json>} on
//// success, {"error": "<msg>"} on failure (G9). `run_in` is pure + testable;
//// `main()` (in the root module) wires system argv and tries the warm daemon
//// path first, falling back to this single-shot path.

import bankai/actors/apply
import bankai/builder
import bankai/graph
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/time
import bankai/types.{InProgress, Open}
import gleam/int
import gleam/json
import gleam/list
import gleam/option

pub const default_workspace = ".bankai"

/// Run a command against a workspace. Output is always a JSON envelope:
/// {"ok": <json>} or {"error": "<msg>"} (G9). No-args prints plain help.
pub fn run_in(workspace: String, argv: List(String)) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  case argv {
    [] -> usage()
    ["init", ..] -> envelope(init_cmd(workspace))
    ["create", title, ..] -> envelope(create_cmd(workspace, tasks_path, title))
    ["list", ..] -> envelope(list_cmd(tasks_path))
    ["ready", ..] -> envelope(ready_cmd(tasks_path))
    ["show", id, ..] -> envelope(show_cmd(tasks_path, id))
    ["dep", "add", task_id, blocker_id, ..] ->
      envelope(dep_add_cmd(tasks_path, task_id, blocker_id))
    ["dep", ..] -> envelope(Error("usage: dep add <task-id> <blocker-id>"))
    ["update", id, "--claim", ..rest] ->
      envelope(claim_cmd(tasks_path, id, rest))
    ["update", id, status, ..] -> envelope(update_cmd(tasks_path, id, status))
    ["update", ..] ->
      envelope(Error(
        "usage: update <id> <status> | update <id> --claim [assignee]",
      ))
    ["inspect", hash, ..] -> envelope(inspect_cmd(tasks_path, hash))
    ["prime", ..] -> envelope(Ok(json.string(prime_text())))
    ["sync", ..] -> envelope(sync_cmd(tasks_path))
    [cmd, ..] -> envelope(Error("unknown command: " <> cmd))
  }
}

/// Wrap a Result into the G9 envelope: {"ok": <json>} / {"error": "<msg>"}.
fn envelope(r: Result(json.Json, String)) -> String {
  case r {
    Ok(j) -> json.to_string(json.object([#("ok", j)]))
    Error(msg) -> json.to_string(json.object([#("error", json.string(msg))]))
  }
}

// --- commands ---

fn init_cmd(workspace: String) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  Ok(json.string("initialized bankai workspace at " <> workspace))
}

fn create_cmd(
  workspace: String,
  tasks_path: String,
  title: String,
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  let now = time.now()
  // G12: id derived from the content hash (bk-XXXX), not the clock.
  let task =
    builder.build_with_derived_id(title, "", Open, option.None, 1, now, now, [])
  let index = store.put(load_store(tasks_path), task)
  let _ = jsonl.flush(store.list(index), to: tasks_path)
  Ok(serde.task_to_json(task))
}

fn list_cmd(tasks_path: String) -> Result(json.Json, String) {
  Ok(
    load_store(tasks_path)
    |> store.current_tasks()
    |> json.array(of: serde.task_to_json),
  )
}

fn ready_cmd(tasks_path: String) -> Result(json.Json, String) {
  Ok(
    load_store(tasks_path)
    |> store.current_tasks()
    |> graph.ready_tasks()
    |> json.array(of: serde.task_to_json),
  )
}

// G2 — find by id, print JSON.
fn show_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  case store.find_by_id(load_store(tasks_path), id) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no such task: " <> id)
  }
}

// G1 — bankai dep add <task-id> <blocker-id>: task-id becomes blocked by
// blocker-id. Cycle-safe (graph.would_cycle) and idempotent (apply.relation
// dedups — BUG-04). Both ids must exist.
fn dep_add_cmd(
  tasks_path: String,
  task_id: String,
  blocker_id: String,
) -> Result(json.Json, String) {
  let index = load_store(tasks_path)
  case store.find_by_id(index, task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(task) ->
      case store.find_by_id(index, blocker_id) {
        Error(Nil) -> Error("no such blocker task: " <> blocker_id)
        Ok(_) ->
          case
            graph.would_cycle(graph.all_edges(store.current_tasks(index)), #(
              task_id,
              blocker_id,
            ))
          {
            True ->
              Error(
                "relation would create a cycle: "
                <> task_id
                <> " -> "
                <> blocker_id,
              )
            False -> {
              let updated = apply.relation(task, blocker_id, time.now())
              let index = store.put(index, updated)
              let _ = jsonl.flush(store.list(index), to: tasks_path)
              Ok(serde.task_to_json(updated))
            }
          }
      }
  }
}

fn update_cmd(
  tasks_path: String,
  id: String,
  status: String,
) -> Result(json.Json, String) {
  case serde.status_from_string(status) {
    Ok(new_status) -> {
      // BUG-01 fix: load the store ONCE and thread it. The previous code
      // reloaded between find_by_id and put, discarding concurrent writes /
      // sibling tasks on flush (TOCTOU + data loss).
      let index = load_store(tasks_path)
      case store.find_by_id(index, id) {
        Ok(task) -> {
          let updated =
            builder.update(task, fn(t) {
              types.Task(..t, status: new_status, updated_at: time.now())
            })
          let index = store.put(index, updated)
          let _ = jsonl.flush(store.list(index), to: tasks_path)
          Ok(serde.task_to_json(updated))
        }
        Error(Nil) -> Error("no such task: " <> id)
      }
    }
    Error(Nil) -> Error("invalid status: " <> status)
  }
}

// G8 — bankai update <id> --claim [assignee]: atomically set InProgress +
// assignee (default "agent").
fn claim_cmd(
  tasks_path: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let assignee = case rest {
    [a, ..] -> a
    [] -> "agent"
  }
  let index = load_store(tasks_path)
  case store.find_by_id(index, id) {
    Ok(task) -> {
      let updated =
        builder.update(task, fn(t) {
          types.Task(
            ..t,
            status: InProgress,
            assignee: option.Some(assignee),
            updated_at: time.now(),
          )
        })
      let index = store.put(index, updated)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(updated))
    }
    Error(Nil) -> Error("no such task: " <> id)
  }
}

fn inspect_cmd(tasks_path: String, hash: String) -> Result(json.Json, String) {
  case store.get_by_hex(load_store(tasks_path), hash) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no task for hash: " <> hash)
  }
}

fn sync_cmd(tasks_path: String) -> Result(json.Json, String) {
  // Reload + dedupe by content hash + normalize back to disk.
  let tasks = store.list(load_store(tasks_path))
  let _ = jsonl.flush(tasks, to: tasks_path)
  Ok(json.string("synced " <> int.to_string(list.length(tasks)) <> " task(s)"))
}

// --- helpers ---

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}

pub fn usage() -> String {
  "bankai — content-addressed task memory\n\n"
  <> "usage: bankai <command> [args]\n\n"
  <> "  create <title>           create a task, print its JSON\n"
  <> "  show <id>                print a task by id (JSON)\n"
  <> "  list                     list all current tasks (JSON array)\n"
  <> "  ready                    list unblocked tasks (JSON array)\n"
  <> "  dep add <id> <blocker>   mark <id> blocked by <blocker>\n"
  <> "  update <id> <status>     set status (open|in_progress|blocked|completed|closed)\n"
  <> "  update <id> --claim [a]  claim: set in_progress + assignee (default: agent)\n"
  <> "  inspect <hash>           render the task for a content hash\n"
  <> "  prime                    emit agent-injection prompt\n"
  <> "  sync                     reconcile + flush .bankai/tasks.jsonl\n"
  <> "  init                     initialize .bankai/\n"
  <> "  serve                    run the daemon (warm JSON-RPC socket path)\n\n"
  <> "all command output is a JSON envelope: {\"ok\": ...} / {\"error\": ...}"
}

pub fn prime_text() -> String {
  "You are an agent operating against the bankai task-memory mesh.\n"
  <> "Task identity is content-addressed (SHA-256 over canonical state).\n"
  <> "IDs are short hash prefixes (bk-XXXX). Before starting work: run\n"
  <> "`bankai ready`, claim an unblocked task (`bankai update <id> --claim`),\n"
  <> "then mark it in_progress. On completion run `bankai update <id> completed`.\n"
  <> "Use `bankai show <id>` / `bankai inspect <hash>` to read state, and\n"
  <> "`bankai dep add <id> <blocker>` to wire dependencies. Mobile validation\n"
  <> "rules may be registered and executed by content hash (allow-list-gated)."
}
