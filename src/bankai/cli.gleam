//// The bankai CLI — single-shot invocation over the JSONL-backed store.
////
//// Every command result is wrapped in a JSON envelope: {"ok": <json>} on
//// success, {"error": "<msg>"} on failure (G9). `run_in` is pure + testable;
//// `main()` (in the root module) wires system argv and tries the warm daemon
//// path first, falling back to this single-shot path.

import bankai/actors/apply
import bankai/builder
import bankai/compact
import bankai/graph
import bankai/memory
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/sync_peer
import bankai/time
import bankai/types.{Blocks, InProgress, Open}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string
import simplifile

pub const default_workspace = ".bankai"

/// Run a command against a workspace. Output is always a JSON envelope:
/// {"ok": <json>} or {"error": "<msg>"} (G9). No-args prints plain help.
pub fn run_in(workspace: String, argv: List(String)) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  case argv {
    [] -> usage()
    ["init", ..] -> envelope(init_cmd(workspace))
    ["create", title, ..rest] ->
      envelope(create_cmd(workspace, tasks_path, title, rest))
    ["list", ..rest] -> envelope(list_cmd(tasks_path, rest))
    ["ready", ..rest] -> envelope(ready_cmd(tasks_path, rest))
    ["show", id, ..] -> envelope(show_cmd(tasks_path, id))
    ["dep", "add", task_id, target_id, ..rest] ->
      envelope(dep_add_cmd(tasks_path, task_id, target_id, rest))
    ["dep", ..] ->
      envelope(Error("usage: dep add <task-id> <target-id> [--type T]"))
    ["update", id, "--label", label, ..] ->
      envelope(label_add_cmd(tasks_path, id, label))
    ["update", id, "--claim", ..rest] ->
      envelope(claim_cmd(tasks_path, id, rest))
    ["update", id, status, ..] -> envelope(update_cmd(tasks_path, id, status))
    ["update", ..] ->
      envelope(Error(
        "usage: update <id> <status> | update <id> --claim [a] | --label <l>",
      ))
    // G4 — agent memory
    ["remember", text, ..] -> envelope(remember_cmd(workspace, text))
    ["memories", ..] -> envelope(memories_cmd(workspace))
    ["inspect", hash, ..] -> envelope(inspect_cmd(tasks_path, hash))
    ["prime", ..] -> envelope(Ok(json.string(prime_text(workspace))))
    // G7 — emit agent-instruction file (claude -> CLAUDE.md, codex -> AGENTS.md)
    ["setup", agent, ..] -> envelope(setup_cmd(agent))
    // G5 — retire closed tasks into archive.jsonl + a summary memory
    ["compact", ..] -> envelope(compact_cmd(workspace, tasks_path))
    // G6 (eventual) — reconcile local, or union-merge a remote tasks.jsonl
    // (--from). The transport (git pull / rsync) is the agent's job; bankai is
    // the merge.
    ["sync", ..rest] -> envelope(sync_cmd(tasks_path, rest))
    // G6 livesync — pull a running peer's task set over TCP and union-merge.
    // (sync-serve, the TCP server, lives in the root main — it blocks.)
    ["sync-pull", ..rest] -> envelope(sync_pull_cmd(workspace, rest))
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
  rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  let now = time.now()
  let labels = parse_labels(rest)
  let priority = parse_priority(rest)
  case parse_parent(rest) {
    // G10: hierarchical subtask id "<parent>.<n>" (parent must exist).
    option.Some(parent_id) -> {
      let index = load_store(tasks_path)
      case store.find_by_id(index, parent_id) {
        Error(Nil) -> Error("no such parent task: " <> parent_id)
        Ok(_) -> {
          let id = next_child_id(index, parent_id)
          let task =
            builder.build(
              id,
              title,
              "",
              Open,
              option.None,
              priority,
              now,
              now,
              [],
            )
          // build defaults labels: []; apply any --label via a rehashed spread.
          let task = case labels {
            [] -> task
            _ -> builder.update(task, fn(t) { types.Task(..t, labels: labels) })
          }
          let index = store.put(index, task)
          let _ = jsonl.flush(store.list(index), to: tasks_path)
          Ok(serde.task_to_json(task))
        }
      }
    }
    // G12: id derived from the content hash (bk-XXXX).
    option.None -> {
      let task =
        builder.build_with_derived_id(
          title,
          "",
          Open,
          option.None,
          priority,
          now,
          now,
          [],
          labels,
        )
      let index = store.put(load_store(tasks_path), task)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(task))
    }
  }
}

fn list_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks = load_store(tasks_path) |> store.current_tasks()
  let tasks = filter_by_label(tasks, parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

fn ready_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> graph.ready_tasks()
  let tasks = filter_by_label(tasks, parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

// G2 — find by id, print JSON.
fn show_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  case store.find_by_id(load_store(tasks_path), id) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no such task: " <> id)
  }
}

// G1 — bankai dep add <task-id> <target-id> [--type T]: add a relation from
// task-id to target-id. Default type Blocks (a dependency — cycle-checked).
// Non-blocks types (relates-to/duplicates/supersedes/replies-to) are
// non-directional annotations and skip the cycle check. Idempotent (BUG-04).
fn dep_add_cmd(
  tasks_path: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let rel_type = parse_relation_type(rest)
  let index = load_store(tasks_path)
  case store.find_by_id(index, task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(task) ->
      case store.find_by_id(index, target_id) {
        Error(Nil) -> Error("no such task: " <> target_id)
        Ok(_) -> {
          // Only Blocks (a dependency) can create a cycle. Non-blocks relations
          // are non-directional, so they skip the cycle check.
          let cycle =
            graph.would_cycle(graph.all_edges(store.current_tasks(index)), #(
              task_id,
              target_id,
            ))
          case rel_type, cycle {
            Blocks, True ->
              Error(
                "relation would create a cycle: "
                <> task_id
                <> " -> "
                <> target_id,
              )
            _, _ -> {
              let updated =
                apply.relation_typed(task, target_id, rel_type, time.now())
              let index = store.put(index, updated)
              let _ = jsonl.flush(store.list(index), to: tasks_path)
              Ok(serde.task_to_json(updated))
            }
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
      // BUG-01 fix: load the store ONCE and thread it.
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

// G3 — bankai update <id> --label <label>: add a label (idempotent).
fn label_add_cmd(
  tasks_path: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  let index = load_store(tasks_path)
  case store.find_by_id(index, id) {
    Ok(task) -> {
      let updated =
        builder.update(task, fn(t) {
          case list.contains(t.labels, label) {
            // idempotent — adding an existing label is a no-op (hash unchanged)
            True -> t
            False ->
              types.Task(
                ..t,
                labels: [label, ..t.labels],
                updated_at: time.now(),
              )
          }
        })
      let index = store.put(index, updated)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(updated))
    }
    Error(Nil) -> Error("no such task: " <> id)
  }
}

// G4 — bankai remember "insight": content-address a memory, persist it, return it.
fn remember_cmd(workspace: String, text: String) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  let path = workspace <> "/memories.jsonl"
  let existing = case memory.load(from: path) {
    Ok(m) -> m
    Error(_) -> []
  }
  let mem = memory.new(text, time.now())
  let _ = memory.flush([mem, ..existing], to: path)
  Ok(memory.memory_to_json(mem))
}

// G4 — bankai memories: list all persisted memories.
fn memories_cmd(workspace: String) -> Result(json.Json, String) {
  let path = workspace <> "/memories.jsonl"
  let mems = case memory.load(from: path) {
    Ok(m) -> m
    Error(_) -> []
  }
  Ok(json.array(mems, of: memory.memory_to_json))
}

fn inspect_cmd(tasks_path: String, hash: String) -> Result(json.Json, String) {
  case store.get_by_hex(load_store(tasks_path), hash) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no task for hash: " <> hash)
  }
}

// G6 (eventual) — bankai sync: reconcile local, or union-merge a remote
// tasks.jsonl (--from). The transport (git pull / rsync) is the agent's job;
// bankai is the (content-addressed, deterministic) merge primitive.
fn sync_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case parse_from(rest) {
    option.Some(remote_path) -> {
      let local = store.list(load_store(tasks_path))
      case jsonl.load(from: remote_path) {
        Error(_) -> Error("could not read remote: " <> remote_path)
        Ok(remote_tasks) -> {
          let result = merge.merge(local, remote_tasks)
          let _ = jsonl.flush(result.tasks, to: tasks_path)
          let nc = list.length(result.conflicts)
          let base =
            "merged " <> int.to_string(list.length(result.tasks)) <> " task(s)"
          Ok(
            json.string(case nc {
              0 -> base
              _ -> base <> " (" <> int.to_string(nc) <> " conflict(s))"
            }),
          )
        }
      }
    }
    option.None -> {
      let tasks = store.list(load_store(tasks_path))
      let _ = jsonl.flush(tasks, to: tasks_path)
      Ok(json.string(
        "synced " <> int.to_string(list.length(tasks)) <> " task(s)",
      ))
    }
  }
}

// G6 livesync — bankai sync-pull: connect to a running peer's sync server
// (bankai sync-serve), pull its task set over TCP, union-merge into local.
fn sync_pull_cmd(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let host = parse_host(rest)
  let port = sync_peer.parse_port(rest, sync_peer.default_port)
  case sync_peer.pull(workspace, host, port) {
    Error(msg) -> Error(msg)
    Ok(n) ->
      Ok(json.string(
        "pulled "
        <> int.to_string(n)
        <> " task(s) from "
        <> host
        <> ":"
        <> int.to_string(port)
        <> " (union-merged)",
      ))
  }
}

// G5 — bankai compact: retire Closed tasks into archive.jsonl + a memory.
fn compact_cmd(
  workspace: String,
  tasks_path: String,
) -> Result(json.Json, String) {
  Ok(json.string(compact.run(workspace, tasks_path)))
}

// G7 — bankai setup <agent>: write an agent-instruction file into the project
// (cwd) so Claude Code / Codex / opencode discover the bankai workflow.
fn setup_cmd(agent: String) -> Result(json.Json, String) {
  let filename = case agent {
    "claude" -> "CLAUDE.md"
    "codex" -> "AGENTS.md"
    other -> other <> ".md"
  }
  let _ = simplifile.write(agent_instructions(), to: filename)
  Ok(json.string("wrote " <> filename <> " (bankai agent instructions)"))
}

// --- helpers ---

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
  }
}

/// G6 (eventual): the value after the first `--from`, if any.
fn parse_from(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--from", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_from(rest)
  }
}

/// G6 livesync: the value after the first `--host` (default "localhost").
fn parse_host(args: List(String)) -> String {
  case args {
    ["--host", v, ..] -> v
    [_, ..rest] -> parse_host(rest)
    [] -> "localhost"
  }
}

/// dep add --type: the relation type after `--type` (default Blocks). Reuses
/// serde's mapping (single source of truth). Invalid → Blocks.
fn parse_relation_type(args: List(String)) -> types.RelationType {
  case args {
    ["--type", v, ..] ->
      case serde.relation_from_string(v) {
        Ok(r) -> r
        Error(_) -> Blocks
      }
    [_, ..rest] -> parse_relation_type(rest)
    [] -> Blocks
  }
}

/// create --priority: the value after `--priority` (default 1).
fn parse_priority(args: List(String)) -> Int {
  case args {
    ["--priority", v, ..] ->
      case int.parse(v) {
        Ok(n) -> n
        Error(_) -> 1
      }
    [_, ..rest] -> parse_priority(rest)
    [] -> 1
  }
}

/// G10: next hierarchical child id "<parent>.<n>" — max existing child number
/// for the parent + 1 (starts at 1). Scans current tasks (unique ids).
fn next_child_id(index: store.Store, parent_id: String) -> String {
  let prefix = parent_id <> "."
  let nums =
    store.current_tasks(index)
    |> list.filter_map(fn(t) {
      case string.starts_with(t.id, prefix) {
        False -> Error(Nil)
        True -> {
          let prefix_len = string.length(prefix)
          let suffix =
            string.slice(t.id, prefix_len, string.length(t.id) - prefix_len)
          case int.parse(suffix) {
            Ok(n) -> Ok(n)
            Error(Nil) -> Error(Nil)
          }
        }
      }
    })
  let next = case list.max(nums, with: int.compare) {
    Ok(m) -> m + 1
    Error(Nil) -> 1
  }
  parent_id <> "." <> int.to_string(next)
}

/// G10: the value after the first `--parent`, if any.
fn parse_parent(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--parent", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_parent(rest)
  }
}

/// Collect the token after each `--label` (G3). Order is reversed (prepend) but
/// labels are an unordered set, sorted again at canonical-encode time.
fn parse_labels(args: List(String)) -> List(String) {
  let #(_, labels) =
    list.fold(args, #(False, []), fn(acc, a) {
      let #(want_value, labels) = acc
      case want_value, a {
        True, v -> #(False, [v, ..labels])
        False, "--label" -> #(True, labels)
        False, _ -> #(False, labels)
      }
    })
  labels
}

/// The first `--label`'s value, if any (used to filter list/ready).
fn parse_label_filter(args: List(String)) -> Option(String) {
  case parse_labels(args) {
    [] -> option.None
    [label, ..] -> option.Some(label)
  }
}

fn filter_by_label(
  tasks: List(types.Task),
  label: Option(String),
) -> List(types.Task) {
  case label {
    option.None -> tasks
    option.Some(l) -> list.filter(tasks, fn(t) { list.contains(t.labels, l) })
  }
}

pub fn usage() -> String {
  "bankai — content-addressed task memory\n\n"
  <> "usage: bankai <command> [args]\n\n"
  <> "  create <title> [--label L].. [--parent <id>] [--priority N]\n"
  <> "                                create a task / subtask\n"
  <> "  show <id>                     print a task by id (JSON)\n"
  <> "  list [--label L]              list current tasks (JSON array)\n"
  <> "  ready [--label L]             list unblocked tasks (JSON array)\n"
  <> "  dep add <id> <target> [--type T]\n"
  <> "                                add a relation (blocks|relates-to|duplicates|supersedes|replies-to)\n"
  <> "  update <id> <status>          open|in_progress|blocked|completed|closed\n"
  <> "  update <id> --claim [a]       claim: in_progress + assignee (default agent)\n"
  <> "  update <id> --label L         add a label\n"
  <> "  remember \"insight\"            persist a content-addressed memory\n"
  <> "  memories                      list persisted memories\n"
  <> "  inspect <hash>                render the task for a content hash\n"
  <> "  compact                       retire closed tasks into archive.jsonl\n"
  <> "  prime                         emit agent-injection prompt (with memories)\n"
  <> "  setup <claude|codex>          write CLAUDE.md / AGENTS.md (agent instructions)\n"
  <> "  sync [--from <path>]          reconcile, or union-merge a remote tasks.jsonl\n"
  <> "  sync-serve [--port N]         run the TCP sync server (peers pull your tasks)\n"
  <> "  sync-pull --host H [--port N] pull + union-merge a running peer's tasks\n"
  <> "  init                          initialize .bankai/\n"
  <> "  serve                         run the daemon (warm JSON-RPC socket path)\n\n"
  <> "all command output is a JSON envelope: {\"ok\": ...} / {\"error\": ...}"
}

/// The bankai workflow, written by `bankai setup` into CLAUDE.md / AGENTS.md so
/// coding agents (Claude Code, Codex, opencode) discover it. (G7)
pub fn agent_instructions() -> String {
  "# Working with bankai\n\n"
  <> "bankai is the task-memory mesh for this project. Tasks are content-addressed\n"
  <> "(SHA-256); IDs are short hash prefixes (bk-XXXX), with hierarchical subtask\n"
  <> "IDs of the form bk-XXXX.N.\n\n"
  <> "## Workflow\n"
  <> "1. `bankai ready` — list unblocked tasks; pick one.\n"
  <> "2. `bankai update <id> --claim` — claim it (sets in_progress + assignee).\n"
  <> "3. Do the work; commit atomically per logical change.\n"
  <> "4. `bankai update <id> completed` — mark done.\n"
  <> "5. `bankai dep add <id> <target> [--type blocks]` — wire a dependency (cycle-safe).\n"
  <> "6. `bankai create <title> [--label L].. [--parent <id>] [--priority N]` — new task/subtask.\n"
  <> "7. `bankai remember \"insight\"` — persist a durable note for future runs.\n"
  <> "8. `bankai compact` — retire closed tasks (keeps `prime` bounded).\n"
  <> "9. `bankai prime` — re-read this workflow + recent memories.\n\n"
  <> "All command output is JSON: {\"ok\": ...} / {\"error\": ...}. A `closed` task\n"
  <> "(won't-do) does NOT satisfy a dependency — only `completed` does."
}

/// The agent-injection prompt. G4: recent persisted memories are appended so
/// agents start a run with durable context.
pub fn prime_text(workspace: String) -> String {
  let base =
    "You are an agent operating against the bankai task-memory mesh.\n"
    <> "Task identity is content-addressed (SHA-256 over canonical state).\n"
    <> "IDs are short hash prefixes (bk-XXXX). Before starting work: run\n"
    <> "`bankai ready`, claim an unblocked task (`bankai update <id> --claim`),\n"
    <> "then mark it in_progress. On completion run `bankai update <id> completed`.\n"
    <> "Use `bankai show <id>` / `bankai inspect <hash>` to read state, and\n"
    <> "`bankai dep add <id> <target>` to wire dependencies. Label work with\n"
    <> "`--label`; prioritize with `--priority`; persist durable insights with\n"
    <> "`bankai remember \"...\"`. Mobile validation rules may be registered and\n"
    <> "executed by content hash (allow-list-gated)."
  let mems_block = case memory.load(from: workspace <> "/memories.jsonl") {
    Ok([]) -> ""
    Ok(mems) -> {
      let lines =
        mems
        |> list.map(fn(m) { "- " <> m.text })
        |> string.join("\n")
      "\n\n## Agent memories (persisted insights)\n" <> lines
    }
    // Missing/unreadable memories file = no memories; prompt is the base text.
    Error(_) -> ""
  }
  base <> mems_block
}
