//// Local CLI maintenance commands and diagnostics.

import bankai/aarondb_bridge
import bankai/backup
import bankai/cli/parser
import bankai/compact
import bankai/memory
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync/merge
import bankai/sync_peer
import bankai/time
import bankai/types.{Blocked, Closed, Completed, InProgress, Open}
import bankai/vector_bridge
import gleam/dict.{type Dict}
import gleam/int
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub fn backup_cmd(
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

pub fn backup_list_cmd(workspace: String) -> Result(json.Json, String) {
  backup.catalog(workspace)
  |> result.map(fn(entries) {
    json.array(entries, fn(e) {
      json.object([
        #("path", json.string(e.path)),
        #("task_count", json.int(e.task_count)),
        #("valid", json.bool(e.valid)),
      ])
    })
  })
}

pub fn backup_preview_cmd(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  backup.divergence_detail(workspace, path)
  |> result.map(fn(div) {
    json.object([
      #("current_count", json.int(div.current_count)),
      #("backup_count", json.int(div.backup_count)),
      #("same_tasks", json.int(div.same_tasks)),
      #(
        "added_in_backup",
        json.array(div.added_in_backup, fn(id) { json.string(id) }),
      ),
      #(
        "missing_in_backup",
        json.array(div.missing_in_backup, fn(id) { json.string(id) }),
      ),
      #(
        "modified_in_backup",
        json.array(div.modified_in_backup, fn(id) { json.string(id) }),
      ),
    ])
  })
}

pub fn backup_restore_cmd(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  backup.restore(workspace, path)
  |> result.map(fn(_) { json.string("restored backup from " <> path) })
}

pub fn backup_prune_cmd(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let keep = case rest {
    ["--keep", k, ..] -> result.unwrap(int.parse(k), 5)
    [k, ..] -> result.unwrap(int.parse(k), 5)
    [] -> 5
  }
  backup.prune(workspace, keep: keep)
  |> result.map(fn(count) {
    json.object([
      #("pruned_count", json.int(count)),
      #("kept", json.int(keep)),
    ])
  })
}

pub type ConflictDetail {
  ConflictDetail(task: String, local: String, remote: String)
}

/// Parse the structured merge-conflict detail format
/// `task=<id> local=<hash> remote=<hash>`. Legacy free-text details return
/// Error and render raw — one payload shape, not a junk drawer.
pub fn parse_conflict_detail(detail: String) -> Result(ConflictDetail, Nil) {
  case string.split(detail, " ") {
    ["task=" <> task, "local=" <> local, "remote=" <> remote] ->
      case task == "" || local == "" || remote == "" {
        True -> Error(Nil)
        False -> Ok(ConflictDetail(task, local, remote))
      }
    _ -> Error(Nil)
  }
}

/// Task ids that already have a pending conflict record.
pub fn pending_conflict_tasks(workspace: String) -> List(String) {
  case sync_peer.list_conflicts(workspace) {
    Ok(records) ->
      records
      |> list.filter_map(fn(r) {
        parse_conflict_detail(r.detail) |> result.map(fn(d) { d.task })
      })
    Error(_) -> []
  }
}

/// Record new merge conflicts durably, skipping ids already pending.
/// Returns the ids recorded (fresh divergences only).
pub fn record_merge_conflicts(
  workspace: String,
  conflicts: List(merge.Conflict),
) -> List(String) {
  let pending = pending_conflict_tasks(workspace)
  conflicts
  |> list.filter(fn(c) { !list.contains(pending, c.id) })
  |> list.map(fn(c) {
    let detail =
      "task="
      <> c.id
      <> " local="
      <> c.local_hash
      <> " remote="
      <> c.remote_hash
    let _ = sync_peer.record_conflict(workspace, "sync", detail)
    c.id
  })
}

pub fn sync_conflicts_cmd(workspace: String) -> Result(json.Json, String) {
  sync_peer.list_conflicts(workspace)
  |> result.map(fn(conflicts) {
    json.array(conflicts, fn(c) {
      let parsed =
        parse_conflict_detail(c.detail)
        |> result.map(fn(d) {
          [
            #("task", json.string(d.task)),
            #("local", json.string(d.local)),
            #("remote", json.string(d.remote)),
          ]
        })
        |> result.unwrap([])
      json.object([
        #("id", json.string(c.id)),
        #("timestamp", json.int(c.timestamp)),
        #("author", json.string(c.author)),
        #("detail", json.string(c.detail)),
        ..parsed
      ])
    })
  })
}

pub fn sync_resolve_cmd(
  workspace: String,
  conflict_id: String,
) -> Result(json.Json, String) {
  sync_peer.resolve_conflict(workspace, conflict_id)
  |> result.map(fn(_) { json.string("resolved conflict " <> conflict_id) })
}

pub fn sync_clear_cmd(workspace: String) -> Result(json.Json, String) {
  sync_peer.clear_conflicts(workspace)
  |> result.map(fn(_) { json.string("cleared all replication conflicts") })
}

pub fn journal_tail_cmd(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let after_offset = case rest {
    ["--after", off, ..] -> result.unwrap(int.parse(off), -1)
    [off, ..] -> result.unwrap(int.parse(off), -1)
    [] -> -1
  }
  mnesia_store.change_tail(workspace, after_offset)
  |> result.map(fn(events) {
    json.object([
      #("after_offset", json.int(after_offset)),
      #("count", json.int(list.length(events))),
      #("events", json.array(events, fn(e) { json.string(e) })),
    ])
  })
}

pub fn export_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let fmt = parser.parse_export_format(rest)
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

pub fn gc_cmd(
  workspace: String,
  tasks_path: String,
) -> Result(json.Json, String) {
  Ok(json.string(compact.run(workspace, tasks_path)))
}

pub fn history_cmd(
  tasks_path: String,
  id: String,
) -> Result(json.Json, String) {
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

pub fn analytics_cmd(tasks_path: String) -> Result(json.Json, String) {
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

pub fn search_cmd(
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

pub fn semantic_duplicates_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let threshold = parser.parse_threshold(rest, 0.78)
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

pub fn show_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
  case store.find_by_id(load_store(tasks_path), id) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no such task: " <> id)
  }
}

pub fn epic_cmd(tasks_path: String, id: String) -> Result(json.Json, String) {
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

pub fn prime_query_text(workspace: String, query: String) -> String {
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
    <> "`bankai remember \"...\"`. Use `bankai rule register`, then explicitly\n"
    <> "approve and evaluate a rule through the daemon; approvals and audits stay local."
  let mems_block = case memory.load(from: workspace <> "/memories.jsonl") {
    Ok([]) -> ""
    Ok(mems) -> {
      let lines =
        mems
        |> list.map(fn(m) { "- " <> m.text })
        |> string.join("\n")
      "\n\n## Agent memories (persisted insights)\n" <> lines
    }
    Error(_) -> ""
  }
  base <> mems_block
}

fn load_store(tasks_path: String) -> store.Store {
  case jsonl.load(from: tasks_path) {
    Ok(tasks) -> store.from_list(tasks)
    Error(_) -> store.new()
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
