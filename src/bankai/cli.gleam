//// The bankai CLI — single-shot invocation over the JSONL-backed store.
////
//// Every command result is wrapped in a JSON envelope: {"ok": <json>} on
//// success, {"error": "<msg>"} on failure (G9). `run_in` is pure + testable;
//// `main()` (in the root module) wires system argv and tries the warm daemon
//// path first, falling back to this single-shot path.

import bankai/aarondb_bridge
import bankai/actors/apply
import bankai/builder
import bankai/compact
import bankai/graph
import bankai/memory
import bankai/message
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/sync_peer
import bankai/time
import bankai/types.{
  type RelationType, type Task, type TaskKind, Blocked, Blocks, Closed,
  Completed, DefaultTask, Duplicates, InProgress, Open, ParentChild,
  Relationship, Task,
}
import bankai/vector_bridge
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
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
    ["count", ..rest] -> envelope(count_cmd(tasks_path, rest))
    ["blocked", ..rest] -> envelope(blocked_cmd(tasks_path, rest))
    ["cycles", ..] -> envelope(cycles_cmd(tasks_path))
    ["duplicates", "--semantic", ..rest] ->
      envelope(semantic_duplicates_cmd(tasks_path, rest))
    ["duplicates", ..] -> envelope(duplicates_cmd(tasks_path))
    ["stale", ..rest] -> envelope(stale_cmd(tasks_path, rest))
    // Phase 1 — aarondb temporal analytics over the content-addressed history
    ["history", id, ..] -> envelope(history_cmd(tasks_path, id))
    ["analytics", ..] -> envelope(analytics_cmd(tasks_path))
    // Phase 2 — full-text search via aarondb BM25
    ["search", ..rest] -> envelope(search_cmd(workspace, tasks_path, rest))
    // Phase C — task-scoped threaded messages
    ["msg", "add", task_id, text, ..rest] ->
      envelope(msg_add_cmd(workspace, tasks_path, task_id, text, rest))
    ["msg", "list", task_id, ..] -> envelope(msg_list_cmd(workspace, task_id))
    ["msg", ..] ->
      envelope(Error(
        "usage: msg add <task-id> <text> [--reply <msg-id>] | msg list <task-id>",
      ))
    // Phase D — maintenance & export
    ["backup", ..] -> envelope(backup_cmd(workspace, tasks_path))
    ["export", ..rest] -> envelope(export_cmd(tasks_path, rest))
    ["gc", ..] -> envelope(gc_cmd(workspace, tasks_path))
    ["show", id, ..] -> envelope(show_cmd(tasks_path, id))
    ["epic", id, ..] -> envelope(epic_cmd(tasks_path, id))
    ["dep", "add", task_id, target_id, ..rest] ->
      envelope(dep_add_cmd(tasks_path, task_id, target_id, rest))
    ["dep", ..] ->
      envelope(Error("usage: dep add <task-id> <target-id> [--type T]"))
    ["update", id, "--label", label, ..] ->
      envelope(label_add_cmd(tasks_path, id, label))
    ["update", id, "--claim", ..rest] ->
      envelope(claim_cmd(tasks_path, id, rest))
    ["update", id, "--priority", n, ..] ->
      envelope(priority_update_cmd(tasks_path, id, n))
    ["update", id, status, ..] -> envelope(update_cmd(tasks_path, id, status))
    ["update", ..] ->
      envelope(Error(
        "usage: update <id> <status> | --claim [a] | --label <l> | --priority N",
      ))
    // G4 — agent memory
    ["remember", text, ..] -> envelope(remember_cmd(workspace, text))
    ["memories", ..] -> envelope(memories_cmd(workspace))
    ["inspect", hash, ..] -> envelope(inspect_cmd(tasks_path, hash))
    ["prime", "--query", query, ..] ->
      envelope(Ok(json.string(prime_query_text(workspace, query))))
    ["prime", ..] -> envelope(Ok(json.string(prime_text(workspace))))
    // G7 — emit agent-instruction file (claude -> CLAUDE.md, codex -> AGENTS.md)
    // Phase F — git hooks + setup matrix
    ["hooks", "install", ..] -> envelope(hooks_install_cmd(workspace))
    ["hooks", ..] -> envelope(Error("usage: hooks install"))
    ["setup", agent, ..] -> envelope(setup_cmd(agent))
    // G5 — retire closed tasks into archive.jsonl + a summary memory
    ["compact", ..] -> envelope(compact_cmd(workspace, tasks_path))
    // G6 (eventual) — reconcile local, or union-merge a remote tasks.jsonl
    // (--from). The transport (git pull / rsync) is the agent's job; bankai is
    // the merge.
    ["sync", ..rest] -> envelope(sync_cmd(workspace, tasks_path, rest))
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

/// Render a normal Bankai JSON error envelope for process-boundary failures.
pub fn error_envelope(message: String) -> String {
  json.to_string(json.object([#("error", json.string(message))]))
}

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
  let kind = parse_kind(rest)
  case parse_parent(rest) {
    // G10: hierarchical subtask id "<parent>.<n>" (parent must exist).
    option.Some(parent_id) -> {
      let index = load_store(tasks_path)
      case store.find_by_id(index, parent_id) {
        Error(Nil) -> Error("no such parent task: " <> parent_id)
        Ok(_) -> {
          // Check for parent hierarchy cycle
          let children =
            index
            |> store.current_tasks()
            |> list.filter(fn(t) { string.starts_with(t.id, parent_id <> ".") })
          case
            graph.would_cycle_parent_chain(
              store.current_tasks(index),
              // We need an id — use a placeholder that won't exist yet
              parent_id <> ".__probe__",
              parent_id,
            )
          {
            True ->
              Error(
                "parent relation would create a hierarchy cycle: " <> parent_id,
              )
            False -> {
              let id = next_child_id(index, parent_id)
              let rels = [
                Relationship(target_id: parent_id, relation: ParentChild),
              ]
              let task =
                builder.build_full(
                  id,
                  title,
                  "",
                  Open,
                  option.None,
                  priority,
                  now,
                  now,
                  rels,
                  labels,
                  option.Some(parent_id),
                  kind,
                )
              let index = store.put(index, task)
              let _ = jsonl.flush(store.list(index), to: tasks_path)
              Ok(serde.task_to_json(task))
            }
          }
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
          option.None,
          kind,
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

/// bankai count [--label L]: number of current tasks (optionally filtered).
fn count_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks = load_store(tasks_path) |> store.current_tasks()
  let tasks = filter_by_label(tasks, parse_label_filter(rest))
  Ok(json.object([#("count", json.int(list.length(tasks)))]))
}

/// bankai blocked [--label L]: tasks currently in the Blocked state.
fn blocked_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.filter(fn(t) { t.status == Blocked })
  let tasks = filter_by_label(tasks, parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

/// bankai cycles: report dependency edges that participate in a cycle (drift
/// detection over the task DAG). Empty array when the graph is acyclic. Pure
/// over graph.cycle_edges — no SQL engine needed.
fn cycles_cmd(tasks_path: String) -> Result(json.Json, String) {
  let edges =
    load_store(tasks_path)
    |> store.current_tasks()
    |> graph.cycle_edges()
  Ok(
    json.array(edges, of: fn(e) {
      let #(from, to) = e
      json.object([
        #("from", json.string(from)),
        #("to", json.string(to)),
      ])
    }),
  )
}

/// bankai duplicates: list task pairs linked by a Duplicates relation. Honest to
/// the data — the relation is a directional annotation (a "duplicates" b), so we
/// emit the pairs the model already holds rather than inventing similarity.
fn duplicates_cmd(tasks_path: String) -> Result(json.Json, String) {
  let pairs =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.flat_map(fn(t) {
      t.relationships
      |> list.filter(fn(r) { r.relation == Duplicates })
      |> list.map(fn(r) { #(t.id, r.target_id) })
    })
  Ok(
    json.array(pairs, of: fn(p) {
      let #(a, b) = p
      json.object([
        #("a", json.string(a)),
        #("b", json.string(b)),
      ])
    }),
  )
}

/// bankai stale [--days N]: active tasks (Open/InProgress/Blocked) not updated
/// in N days (drift). Default 7. Completed/Closed tasks are excluded — a done
/// task that sits idle is not "drift".
fn stale_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let days = parse_days(rest)
  let cutoff = time.now() - days * 86_400
  let tasks =
    load_store(tasks_path)
    |> store.current_tasks()
    |> list.filter(fn(t) { graph.is_active(t.status) && t.updated_at < cutoff })
  Ok(json.array(tasks, of: serde.task_to_json))
}

// Phase C — bankai msg add <task-id> <text> [--reply <msg-id>]:
// content-address a message, persist to messages.jsonl, return it.
fn msg_add_cmd(
  workspace: String,
  tasks_path: String,
  task_id: String,
  text: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  case store.find_by_id(load_store(tasks_path), task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(_) -> {
      let parent = msg_add_parse_reply(rest)
      let msg = message.new(task_id, parent, "agent", text, time.now())
      let path = workspace <> "/messages.jsonl"
      let existing = case message.load(from: path) {
        Ok(m) -> m
        Error(_) -> []
      }
      let _ = message.flush([msg, ..existing], to: path)
      Ok(message.message_to_json(msg))
    }
  }
}

/// bankai msg list <task-id>: return all messages for a task,
/// ordered newest-first (threaded by parent_msg_id).
fn msg_list_cmd(
  workspace: String,
  task_id: String,
) -> Result(json.Json, String) {
  let path = workspace <> "/messages.jsonl"
  let msgs = case message.load(from: path) {
    Ok(m) -> m
    Error(_) -> []
  }
  let task_msgs =
    msgs
    |> list.filter(fn(m) { m.task_id == task_id })
    |> list.sort(fn(a, b) { int.compare(b.ts, a.ts) })
  Ok(json.array(task_msgs, of: message.message_to_json))
}

// Phase D — bankai backup: copy tasks.jsonl to a timestamped
// backup file. Simple, atomic, no deps.
fn backup_cmd(
  workspace: String,
  tasks_path: String,
) -> Result(json.Json, String) {
  case simplifile.read(from: tasks_path) {
    Error(_) -> Error("no tasks file: " <> tasks_path)
    Ok(body) -> {
      let ts = time.now()
      let backup_path = workspace <> "/tasks.jsonl.bak." <> int.to_string(ts)
      case simplifile.write(body, to: backup_path) {
        Error(_) -> Error("backup failed: could not write " <> backup_path)
        Ok(_) ->
          Ok(json.string("backed up " <> tasks_path <> " -> " <> backup_path))
      }
    }
  }
}

// Phase D — bankai export [--format md|json]: render all current
// tasks as a markdown checklist (default) or JSON array.
// The markdown format doubles as a one-way GitHub-issue export
// (rejects full bidirectional GitHub coupling as core).
fn export_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let fmt = parse_export_format(rest)
  let tasks = load_store(tasks_path) |> store.current_tasks()
  case fmt {
    "md" -> {
      let lines =
        tasks
        |> list.map(fn(t) {
          let check = case t.status {
            Completed -> "x"
            Closed -> "x"
            _ -> " "
          }
          "- [" <> check <> "] " <> t.title
        })
      Ok(json.string(string.join(lines, "\n")))
    }
    "json" -> Ok(json.array(tasks, of: serde.task_to_json))
    _ -> Error("unknown format: " <> fmt <> " (use md or json)")
  }
}

// Phase D — bankai gc: retire closed tasks into archive.jsonl.
// Extends compact (same tier+retire semantics) under a name
// that matches the maintenance vocabulary.
fn gc_cmd(workspace: String, tasks_path: String) -> Result(json.Json, String) {
  Ok(json.string(compact.run(workspace, tasks_path)))
}

// Phase 1 — temporal analytics via aarondb.

/// bankai history <id>: status timeline for a task over the content-addressed
/// version history, via an aarondb Datalog query.
fn history_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  let versions = store.list(load_store(tasks_path))
  case aarondb_bridge.db_from_versions(versions) {
    Error(e) -> Error(e)
    Ok(db) -> {
      let timeline = aarondb_bridge.history_timeline(db, id)
      Ok(
        json.array(timeline, of: fn(p) {
          let #(at, status) = p
          json.object([#("at", json.int(at)), #("status", json.string(status))])
        }),
      )
    }
  }
}

/// bankai analytics: aggregate metrics over the current task set via aarondb
/// Datalog queries — counts by status + average cycle time for completed work.
fn analytics_cmd(tasks_path: String) -> Result(json.Json, String) {
  let tasks = store.current_tasks(load_store(tasks_path))
  case aarondb_bridge.db_from_tasks(tasks) {
    Error(e) -> Error(e)
    Ok(db) -> {
      let by_status = aarondb_bridge.count_by_status(db)
      let cycles = aarondb_bridge.cycle_times(db)
      let completed = list.length(cycles)
      let avg = case completed {
        0 -> 0
        n -> int.sum(cycles) / n
      }
      Ok(
        json.object([
          #("total", json.int(list.length(tasks))),
          #("completed", json.int(completed)),
          #("avg_cycle_time_nanoseconds", json.int(avg)),
          #("by_status", status_counts_to_json(by_status)),
        ]),
      )
    }
  }
}

fn status_counts_to_json(counts: Dict(String, Int)) -> json.Json {
  counts
  |> dict.to_list()
  |> list.sort(by: fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(p) {
    let #(k, v) = p
    #(k, json.int(v))
  })
  |> json.object
}

/// bankai search <query>: full-text search across task titles/descriptions and
/// memories via aarondb's BM25 index. Returns ranked matches (score > 0).
fn search_cmd(
  workspace: String,
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let query = string.join(rest, " ")
  let tasks = store.current_tasks(load_store(tasks_path))
  let task_docs =
    list.map(tasks, fn(t) { #("task", t.id, t.title <> " " <> t.description) })
  let mem_docs = case memory.load(from: workspace <> "/memories.jsonl") {
    Ok(mems) ->
      list.map(mems, fn(m) {
        #("memory", store.hash_key(m.content_hash), m.text)
      })
    Error(_) -> []
  }
  let results = aarondb_bridge.search(list.append(task_docs, mem_docs), query)
  Ok(
    json.array(results, of: fn(r) {
      let #(kind, id, score) = r
      json.object([
        #("kind", json.string(kind)),
        #("id", json.string(id)),
        #("score", json.float(score)),
      ])
    }),
  )
}

// Semantic duplicate candidates are deliberately separate from the existing
// explicit Duplicates relation: similarity is a lead for human/agent review,
// not a fact bankai should assert automatically.
fn semantic_duplicates_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let threshold = parse_threshold(rest, 0.78)
  let tasks = store.current_tasks(load_store(tasks_path))
  let docs =
    list.map(tasks, fn(t) {
      vector_bridge.Document("task", t.id, t.title <> " " <> t.description)
    })
  let candidates =
    list.flat_map(tasks, fn(task) {
      let query = task.title <> " " <> task.description
      vector_bridge.search(docs, query, threshold, 6)
      |> list.filter(fn(m) { m.kind == "task" && m.id != task.id })
      |> list.map(fn(m) {
        json.object([
          #("source", json.string(task.id)),
          #("candidate", json.string(m.id)),
          #("score", json.float(m.score)),
          #("backend", json.string(vector_bridge.backend())),
        ])
      })
    })
  Ok(json.array(candidates, of: fn(x) { x }))
}

fn parse_threshold(args: List(String), default: Float) -> Float {
  case args {
    ["--threshold", value, ..] ->
      case float.parse(value) {
        Ok(n) -> n
        Error(Nil) -> default
      }
    [_, ..rest] -> parse_threshold(rest, default)
    [] -> default
  }
}

// Phase 3 — semantic query context. Tasks and memories are indexed together,
// but the returned prompt names the backend and keeps the existing base prompt.
fn prime_query_text(workspace: String, query: String) -> String {
  let tasks_path = workspace <> "/tasks.jsonl"
  let tasks = store.current_tasks(load_store(tasks_path))
  let task_docs =
    list.map(tasks, fn(t) {
      vector_bridge.Document("task", t.id, t.title <> " " <> t.description)
    })
  let mem_docs = case memory.load(from: workspace <> "/memories.jsonl") {
    Ok(mems) ->
      list.map(mems, fn(m) {
        vector_bridge.Document("memory", store.hash_key(m.content_hash), m.text)
      })
    Error(_) -> []
  }
  let matches =
    vector_bridge.search(list.append(task_docs, mem_docs), query, 0.18, 12)
  let context =
    matches
    |> list.map(fn(m) {
      "- ["
      <> m.kind
      <> ":"
      <> m.id
      <> "] "
      <> match_text(m, task_docs, mem_docs)
    })
    |> string.join("\n")
  let base = prime_text(workspace)
  case context {
    "" -> base <> "\n\n## Semantic context\nNo matches for: " <> query
    _ ->
      base
      <> "\n\n## Semantic context ("
      <> vector_bridge.backend()
      <> ")\nQuery: "
      <> query
      <> "\n"
      <> context
  }
}

fn match_text(
  m: vector_bridge.Match,
  tasks: List(vector_bridge.Document),
  memories: List(vector_bridge.Document),
) -> String {
  let docs = list.append(tasks, memories)
  case list.find(docs, fn(d) { d.kind == m.kind && d.id == m.id }) {
    Ok(vector_bridge.Document(_, _, text)) -> text
    Error(Nil) -> ""
  }
}

// G2 — find by id, print JSON.
fn show_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  case store.find_by_id(load_store(tasks_path), id) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no such task: " <> id)
  }
}

/// bankai epic <id>: roll up a parent task's hierarchical children
/// (bk-XXXX.N). Returns children count, per-status breakdown, and
/// completion percentage. Reuses the id-prefix scan already in
/// next_child_id — no new model code.
fn epic_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  let index = load_store(tasks_path)
  case store.find_by_id(index, id) {
    Error(Nil) -> Error("no such task: " <> id)
    Ok(_) -> {
      let prefix = id <> "."
      let children =
        store.current_tasks(index)
        |> list.filter(fn(t) { string.starts_with(t.id, prefix) })
      let total = list.length(children)
      let by_status =
        list.fold(children, #(0, 0, 0, 0, 0), fn(acc, t) {
          let #(open, in_progress, blocked, completed, closed) = acc
          case t.status {
            Open -> #(open + 1, in_progress, blocked, completed, closed)
            InProgress -> #(open, in_progress + 1, blocked, completed, closed)
            Blocked -> #(open, in_progress, blocked + 1, completed, closed)
            Completed -> #(open, in_progress, blocked, completed + 1, closed)
            Closed -> #(open, in_progress, blocked, completed, closed + 1)
          }
        })
      let #(open, in_progress, blocked, completed, closed) = by_status
      let done = completed + closed
      let pct = case total {
        0 -> 0.0
        _ -> int.to_float(done) /. int.to_float(total) *. 100.0
      }
      Ok(
        json.object([
          #("parent", json.string(id)),
          #("children", json.int(total)),
          #(
            "status",
            json.object([
              #("open", json.int(open)),
              #("in_progress", json.int(in_progress)),
              #("blocked", json.int(blocked)),
              #("completed", json.int(completed)),
              #("closed", json.int(closed)),
            ]),
          ),
          #("completion_pct", json.float(pct)),
        ]),
      )
    }
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
              Task(..t, status: new_status, updated_at: time.now())
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
          Task(
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
              Task(..t, labels: [label, ..t.labels], updated_at: time.now())
          }
        })
      let index = store.put(index, updated)
      let _ = jsonl.flush(store.list(index), to: tasks_path)
      Ok(serde.task_to_json(updated))
    }
    Error(Nil) -> Error("no such task: " <> id)
  }
}

/// bankai update <id> --priority N: set the task's priority field.
fn priority_update_cmd(
  tasks_path: String,
  id: String,
  priority_str: String,
) -> Result(json.Json, String) {
  case int.parse(priority_str) {
    Error(_) -> Error("invalid priority: " <> priority_str)
    Ok(priority) -> {
      let index = load_store(tasks_path)
      case store.find_by_id(index, id) {
        Ok(task) -> {
          let updated =
            builder.update(task, fn(t) {
              Task(..t, priority: priority, updated_at: time.now())
            })
          let index = store.put(index, updated)
          let _ = jsonl.flush(store.list(index), to: tasks_path)
          Ok(serde.task_to_json(updated))
        }
        Error(Nil) -> Error("no such task: " <> id)
      }
    }
  }
}

// G4 — bankai remember "insight": content-address a memory, persist it, return it.
fn remember_cmd(workspace: String, text: String) -> Result(json.Json, String) {
  memory.remember(workspace, text) |> result.map(memory.memory_to_json)
}

// G4 — bankai memories: list all persisted memories.
fn memories_cmd(workspace: String) -> Result(json.Json, String) {
  memory.all(workspace)
  |> result.map(fn(memories) { json.array(memories, of: memory.memory_to_json) })
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
// --peers: pull from multiple peers (a file of host:port lines) and
// union-merge all. Convergence is free (content-addressed).
fn sync_cmd(
  workspace: String,
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case parse_peers(rest) {
    option.Some(peers_file) -> {
      case simplifile.read(from: peers_file) {
        Error(_) -> Error("could not read peers file: " <> peers_file)
        Ok(contents) -> {
          let peers =
            contents
            |> string.split("\n")
            |> list.filter(fn(line) { line != "" })
          let reports =
            list.fold(peers, [], fn(reports, peer_line) {
              let host_port = string.split(peer_line, ":")
              case host_port {
                [host, port_str, ..] -> {
                  case int.parse(port_str) {
                    Ok(port) -> {
                      case sync_peer.fetch(host, port) {
                        Error(msg) -> [
                          #("error", host <> ":" <> port_str, msg),
                          ..reports
                        ]
                        Ok(snapshot) -> [
                          #(
                            "fetched",
                            host <> ":" <> port_str,
                            int.to_string(list.length(snapshot.versions)),
                          ),
                          ..reports
                        ]
                      }
                    }
                    Error(_) -> [
                      #("error", peer_line, "invalid port"),
                      ..reports
                    ]
                  }
                }
                _ -> [
                  #("error", peer_line, "invalid host:port format"),
                  ..reports
                ]
              }
            })
          let report_lines =
            reports
            |> list.map(fn(r) {
              let #(kind, peer, msg) = r
              case kind {
                "fetched" -> "fetched " <> msg <> " task(s) from " <> peer
                "error" -> "error from " <> peer <> ": " <> msg
                _ -> peer <> ": " <> msg
              }
            })
          Ok(json.string(string.join(report_lines, "\n")))
        }
      }
    }
    option.None -> {
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
                "merged "
                <> int.to_string(list.length(result.tasks))
                <> " task(s)"
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
  }
}

// Transport-only helper retained for direct callers. The main CLI routes
// sync-pull through the daemon, which performs the transactional import.
fn sync_pull_cmd(
  _workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let host = parse_host(rest)
  let port = sync_peer.parse_port(rest, sync_peer.default_port)
  sync_peer.fetch(host, port)
  |> result.map(fn(snapshot) {
    json.string(
      "fetched "
      <> int.to_string(list.length(snapshot.versions))
      <> " immutable version(s) and "
      <> int.to_string(list.length(snapshot.heads))
      <> " head(s) from "
      <> host
      <> ":"
      <> int.to_string(port)
      <> "; import requires the daemon",
    )
  })
}

// G5 — bankai compact: retire Closed tasks into archive.jsonl + a memory.
fn compact_cmd(
  workspace: String,
  tasks_path: String,
) -> Result(json.Json, String) {
  Ok(json.string(compact.run(workspace, tasks_path)))
}

// Phase F — bankai hooks install: writes a .git/hooks/pre-commit
// script that runs bankai compact on every commit.
fn hooks_install_cmd(workspace: String) -> Result(json.Json, String) {
  let hooks_dir = workspace <> "/.git/hooks"
  let hook_path = hooks_dir <> "/pre-commit"
  let hook_content =
    "#!/bin/sh\n"
    <> "# bankai pre-commit hook — auto-compact on commit\n"
    <> "cd \"$(git rev-parse --show-toplevel)\"\n"
    <> "bankai compact\n"
  case simplifile.create_directory_all(hooks_dir) {
    Error(_) -> Error("could not create hooks dir: " <> hooks_dir)
    Ok(_) -> {
      case simplifile.write(hook_content, to: hook_path) {
        Error(_) -> Error("could not write hook: " <> hook_path)
        Ok(_) ->
          Ok(json.string(
            "installed pre-commit hook at "
            <> hook_path
            <> " (make it executable: chmod +x "
            <> hook_path
            <> ")",
          ))
      }
    }
  }
}

// G7 — bankai setup <agent>: write an agent-instruction file into the project
// (cwd) so Claude Code / Codex / Cursor / opencode discover the bankai workflow.
// Extended with factory/mux/opencode/windsurf (the setup matrix).
fn setup_cmd(agent: String) -> Result(json.Json, String) {
  let filename = case agent {
    "claude" -> "CLAUDE.md"
    "codex" -> "AGENTS.md"
    "cursor" -> ".cursorrules"
    "factory" -> ".factory.md"
    "mux" -> ".mux.md"
    "opencode" -> ".opencode.md"
    "windsurf" -> ".windsurf.md"
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

/// sync --peers: the value after the first `--peers`, if any.
fn parse_peers(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--peers", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_peers(rest)
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

/// stale --days: the value after `--days` (default 7). Invalid -> 7.
fn parse_days(args: List(String)) -> Int {
  case args {
    ["--days", v, ..] ->
      case int.parse(v) {
        Ok(n) -> n
        Error(_) -> 7
      }
    [_, ..rest] -> parse_days(rest)
    [] -> 7
  }
}

/// msg add --reply: the value after `--reply` (empty = top-level).
fn msg_add_parse_reply(args: List(String)) -> String {
  case args {
    ["--reply", v, ..] -> v
    [_, ..rest] -> msg_add_parse_reply(rest)
    [] -> ""
  }
}

/// export --format: the value after `--format` (default "md").
fn parse_export_format(args: List(String)) -> String {
  case args {
    ["--format", v, ..] -> v
    [_, ..rest] -> parse_export_format(rest)
    [] -> "md"
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

fn parse_kind(args: List(String)) -> TaskKind {
  case args {
    ["--kind", value, ..] -> serde.kind_from_string(value)
    [_, ..rest] -> parse_kind(rest)
    [] -> DefaultTask
  }
}

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

/// The first `--label`'s value, if any (used to filter list/ready/count/blocked).
fn parse_label_filter(args: List(String)) -> Option(String) {
  case parse_labels(args) {
    [] -> option.None
    [label, ..] -> option.Some(label)
  }
}

fn filter_by_label(tasks: List(Task), label: Option(String)) -> List(Task) {
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
  <> "  epic <id>                     roll up a parent's hierarchical children\n"
  <> "  list [--label L]              list current tasks (JSON array)\n"
  <> "  ready [--label L]             list unblocked tasks (JSON array)\n"
  <> "  count [--label L]             count current tasks\n"
  <> "  blocked [--label L]           list blocked tasks (JSON array)\n"
  <> "  cycles                        report dependency edges on a cycle\n"
  <> "  duplicates                    list task pairs linked by Duplicates\n"
  <> "  duplicates --semantic [--threshold N]\n"
  <> "                                list similarity candidates (review only)\n"
  <> "  stale [--days N]              active tasks not updated in N days (drift)\n"
  <> "  history <id>                  status timeline for a task (aarondb)\n"
  <> "  analytics                     counts by status + avg cycle time (aarondb)\n"
  <> "  search <query>                full-text search across tasks/memories (BM25)\n"
  <> "  msg list <task-id>            list messages for a task (newest first)\n"
  <> "  msg add <task-id> <text> [--reply <msg-id>]\n"
  <> "                                post a threaded message\n"
  <> "  msg list <task-id>            list messages for a task (newest first)\n"
  <> "  backup                        copy tasks.jsonl to a timestamped .bak\n"
  <> "  export [--format md|json]     render tasks as checklist or JSON\n"
  <> "  gc                            retire closed tasks into archive.jsonl\n"
  <> "  dep add <id> <target> [--type T]\n"
  <> "                                add a relation (blocks|relates-to|duplicates|supersedes|replies-to)\n"
  <> "  update <id> <status>          open|in_progress|blocked|completed|closed\n"
  <> "  update <id> --claim [a]       claim: in_progress + assignee (default agent)\n"
  <> "  update <id> --label L         add a label\n"
  <> "  update <id> --priority N      set the priority\n"
  <> "  remember \"insight\"            persist a content-addressed memory\n"
  <> "  memories                      list persisted memories\n"
  <> "  inspect <hash>                render the task for a content hash\n"
  <> "  compact                       retire closed tasks into archive.jsonl\n"
  <> "  prime [--query <text>]       emit agent prompt, optionally with relevant context\n"
  <> "  setup <claude|codex|cursor>   write agent-instruction file\n"
  <> "  sync [--from <path>]          import a portable JSONL snapshot\n"
  <> "  sync --peers <file>           replicate immutable history from peers\n"
  <> "  sync-serve [--port N]         serve immutable history + current heads\n"
  <> "  sync-pull --host H [--port N] replicate immutable history from a peer\n"
  <> "  init                          initialize .bankai/\n"
  <> "  serve                         run the daemon (warm JSON-RPC socket path)\n\n"
  <> "all command output is a JSON envelope: {\"ok\": ...} / {\"error\": ...}"
}

/// The bankai workflow, written by `bankai setup` into CLAUDE.md / AGENTS.md /
/// .cursorrules so coding agents (Claude Code, Codex, Cursor, opencode) discover
/// it. (G7)
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
  <> "9. `bankai prime [--query \"topic\"]` — retrieve relevant context when needed.\n\n"
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
