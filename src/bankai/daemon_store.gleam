//// Daemon-owned transactional command service.

import bankai/aarondb_bridge
import bankai/actors/apply
import bankai/builder
import bankai/cli
import bankai/compact
import bankai/graph
import bankai/memory
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/sync_peer
import bankai/time
import bankai/types.{
  type Task, type TaskKind, Blocked, Blocks, CausedBy, Closed, Completed,
  ConditionalBlocks, DefaultTask, DiscoveredFrom, Duplicates, Gate, InProgress,
  Open, ParentChild, RelatesTo, Relationship, RepliesTo, Supersedes, Task,
  Tracks, Validates, WaitsFor,
}
import bankai/vector_bridge
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

pub fn list_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(fn(index) {
    index
    |> store.current_tasks()
    |> filter_by_label(parse_label_filter(rest))
    |> json.array(of: serde.task_to_json)
  })
}

pub fn ready_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(fn(index) {
    index
    |> store.current_tasks()
    |> graph.ready_tasks_at(time.now())
    |> filter_by_label(parse_label_filter(rest))
    |> json.array(of: serde.task_to_json)
  })
}

pub fn boot(workspace: String) -> Result(Nil, String) {
  mnesia_store.init(workspace)
  |> result.try(fn(_) {
    jsonl.load(from: workspace <> "/tasks.jsonl")
    |> result.try(fn(tasks) {
      mnesia_store.import_legacy_if_needed(workspace, store.from_list(tasks))
    })
  })
}

pub fn show_task(workspace: String, id: String) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.try(fn(tasks) {
    mnesia_store.get_current(workspace, id)
    |> result.map(fn(task) {
      let blockers =
        task.relationships
        |> list.filter(fn(relation) {
          graph.is_blocking_relation(relation.relation)
          && !list.any(tasks, fn(candidate) {
            candidate.id == relation.target_id && candidate.status == Completed
          })
        })
      let children =
        list.filter(tasks, fn(candidate) {
          candidate.parent_id == option.Some(id)
        })
      json.object([
        #("task", serde.task_to_json(task)),
        #("children", json.array(children, of: serde.task_to_json)),
        #(
          "blocking",
          json.array(blockers, of: fn(relation) {
            json.object([#("target_id", json.string(relation.target_id))])
          }),
        ),
        #("deferred", json.bool(graph.is_deferred(task, time.now()))),
      ])
    })
  })
}

pub fn count_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> filter_by_label(parse_label_filter(rest))
    |> list.length
    |> json.int
    |> fn(count) { json.object([#("count", count)]) }
  })
}

pub fn blocked_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> list.filter(fn(task) { task.status == Blocked })
    |> filter_by_label(parse_label_filter(rest))
    |> json.array(of: serde.task_to_json)
  })
}

pub fn cycle_edges(workspace: String) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> graph.cycle_edges()
    |> json.array(of: fn(edge) {
      let #(from, to) = edge
      json.object([#("from", json.string(from)), #("to", json.string(to))])
    })
  })
}

pub fn duplicate_pairs(workspace: String) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> list.flat_map(fn(task) {
      task.relationships
      |> list.filter(fn(relation) { relation.relation == Duplicates })
      |> list.map(fn(relation) { #(task.id, relation.target_id) })
    })
    |> json.array(of: fn(pair) {
      let #(a, b) = pair
      json.object([#("a", json.string(a)), #("b", json.string(b))])
    })
  })
}

pub fn stale_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let cutoff = time.now() - parse_days(rest) * 86_400
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> list.filter(fn(task) {
      graph.is_active(task.status) && task.updated_at < cutoff
    })
    |> json.array(of: serde.task_to_json)
  })
}

pub fn history(workspace: String, id: String) -> Result(json.Json, String) {
  mnesia_store.version_store(workspace)
  |> result.try(fn(index) { aarondb_bridge.db_from_versions(store.list(index)) })
  |> result.map(fn(db) {
    aarondb_bridge.history_timeline(db, id)
    |> json.array(of: fn(point) {
      let #(at, status) = point
      json.object([#("at", json.int(at)), #("status", json.string(status))])
    })
  })
}

pub fn analytics(workspace: String) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.try(fn(tasks) {
    aarondb_bridge.db_from_tasks(tasks)
    |> result.map(fn(db) {
      let cycles = aarondb_bridge.cycle_times(db)
      let completed = list.length(cycles)
      let average = case completed {
        0 -> 0
        n -> int.sum(cycles) / n
      }
      json.object([
        #("total", json.int(list.length(tasks))),
        #("completed", json.int(completed)),
        #("avg_cycle_time_nanoseconds", json.int(average)),
        #(
          "by_status",
          status_counts_to_json(aarondb_bridge.count_by_status(db)),
        ),
      ])
    })
  })
}

pub fn search(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    let task_docs =
      list.map(tasks, fn(task) {
        #("task", task.id, task.title <> " " <> task.description)
      })
    let memory_docs = memory_docs(workspace)
    aarondb_bridge.search(
      list.append(task_docs, memory_docs),
      string.join(rest, " "),
    )
    |> json.array(of: search_result_json)
  })
}

pub fn semantic_duplicates(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    let docs = task_documents(tasks)
    tasks
    |> list.flat_map(fn(task) {
      vector_bridge.search(
        docs,
        task.title <> " " <> task.description,
        parse_threshold(rest, 0.78),
        6,
      )
      |> list.filter(fn(match) { match.kind == "task" && match.id != task.id })
      |> list.map(fn(match) {
        json.object([
          #("source", json.string(task.id)),
          #("candidate", json.string(match.id)),
          #("score", json.float(match.score)),
          #("backend", json.string(vector_bridge.backend())),
        ])
      })
    })
    |> json.array(of: fn(value) { value })
  })
}

pub fn inspect(workspace: String, hash: String) -> Result(json.Json, String) {
  mnesia_store.version_store(workspace)
  |> result.try(fn(index) {
    case store.get_by_hex(index, hash) {
      Ok(task) -> Ok(serde.task_to_json(task))
      Error(Nil) -> Error("no task for hash: " <> hash)
    }
  })
}

pub fn prime_query(
  workspace: String,
  query: String,
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    let task_docs = task_documents(tasks)
    let memory_docs = memory_documents(workspace)
    let matches =
      vector_bridge.search(list.append(task_docs, memory_docs), query, 0.18, 12)
    let context =
      matches
      |> list.map(fn(match) {
        "-["
        <> match.kind
        <> ":"
        <> match.id
        <> "] "
        <> match_text(match, task_docs, memory_docs)
      })
      |> string.join("\n")
    let base = cli.prime_text(workspace)
    case context {
      "" ->
        json.string(
          base <> "\n\n## Semantic context\nNo matches for: " <> query,
        )
      _ ->
        json.string(
          base
          <> "\n\n## Semantic context ("
          <> vector_bridge.backend()
          <> ")\nQuery: "
          <> query
          <> "\n"
          <> context,
        )
    }
  })
}

pub fn epic(workspace: String, id: String) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.try(fn(index) {
    case store.find_by_id(index, id) {
      Error(Nil) -> Error("no such task: " <> id)
      Ok(_) -> Ok(epic_json(store.current_tasks(index), id))
    }
  })
}

pub fn remember(workspace: String, text: String) -> Result(json.Json, String) {
  memory.remember(workspace, text) |> result.map(memory.memory_to_json)
}

pub fn memories(workspace: String) -> Result(json.Json, String) {
  memory.all(workspace)
  |> result.map(fn(memories) { json.array(memories, of: memory.memory_to_json) })
}

/// Compact operates over the explicit JSONL interchange projection. Export
/// first so compact consumes the same complete history direct CLI users see;
/// import the survivors back through Mnesia to keep daemon reads authoritative.
pub fn compact(workspace: String) -> Result(json.Json, String) {
  export_jsonl(workspace)
  |> result.try(fn(_) {
    let message = compact.run(workspace, workspace <> "/tasks.jsonl")
    jsonl.load(from: workspace <> "/tasks.jsonl")
    |> result.try(fn(tasks) {
      mnesia_store.replace_current_snapshot(workspace, store.from_list(tasks))
    })
    |> result.map(fn(_) { json.string(message) })
  })
}

fn current_tasks(workspace: String) -> Result(List(Task), String) {
  mnesia_store.current_store(workspace) |> result.map(store.current_tasks)
}

fn parse_days(args: List(String)) -> Int {
  case args {
    ["--days", value, ..] ->
      case int.parse(value) {
        Ok(days) -> days
        Error(_) -> 7
      }
    [_, ..rest] -> parse_days(rest)
    [] -> 7
  }
}

fn parse_threshold(args: List(String), default: Float) -> Float {
  case args {
    ["--threshold", value, ..] ->
      case float.parse(value) {
        Ok(threshold) -> threshold
        Error(_) -> default
      }
    [_, ..rest] -> parse_threshold(rest, default)
    [] -> default
  }
}

fn status_counts_to_json(counts: Dict(String, Int)) -> json.Json {
  counts
  |> dict.to_list()
  |> list.sort(by: fn(a, b) { string.compare(a.0, b.0) })
  |> list.map(fn(pair) { #(pair.0, json.int(pair.1)) })
  |> json.object
}

fn memory_docs(workspace: String) -> List(#(String, String, String)) {
  case memory.load(from: workspace <> "/memories.jsonl") {
    Ok(memories) ->
      list.map(memories, fn(memory) {
        #("memory", store.hash_key(memory.content_hash), memory.text)
      })
    Error(_) -> []
  }
}

fn task_documents(tasks: List(Task)) -> List(vector_bridge.Document) {
  list.map(tasks, fn(task) {
    vector_bridge.Document(
      "task",
      task.id,
      task.title <> " " <> task.description,
    )
  })
}

fn memory_documents(workspace: String) -> List(vector_bridge.Document) {
  case memory.load(from: workspace <> "/memories.jsonl") {
    Ok(memories) ->
      list.map(memories, fn(memory) {
        vector_bridge.Document(
          "memory",
          store.hash_key(memory.content_hash),
          memory.text,
        )
      })
    Error(_) -> []
  }
}

fn search_result_json(result: #(String, String, Float)) -> json.Json {
  let #(kind, id, score) = result
  json.object([
    #("kind", json.string(kind)),
    #("id", json.string(id)),
    #("score", json.float(score)),
  ])
}

fn match_text(
  match: vector_bridge.Match,
  tasks: List(vector_bridge.Document),
  memories: List(vector_bridge.Document),
) -> String {
  case
    list.find(list.append(tasks, memories), fn(document) {
      document.kind == match.kind && document.id == match.id
    })
  {
    Ok(vector_bridge.Document(_, _, text)) -> text
    Error(Nil) -> ""
  }
}

fn epic_json(tasks: List(Task), id: String) -> json.Json {
  let children =
    list.filter(tasks, fn(task) { task.parent_id == option.Some(id) })
  let #(open, in_progress, blocked, completed, closed) =
    list.fold(children, #(0, 0, 0, 0, 0), fn(counts, task) {
      let #(open, in_progress, blocked, completed, closed) = counts
      case task.status {
        Open -> #(open + 1, in_progress, blocked, completed, closed)
        InProgress -> #(open, in_progress + 1, blocked, completed, closed)
        Blocked -> #(open, in_progress, blocked + 1, completed, closed)
        Completed -> #(open, in_progress, blocked, completed + 1, closed)
        Closed -> #(open, in_progress, blocked, completed, closed + 1)
      }
    })
  let total = list.length(children)
  let percent = case total {
    0 -> 0.0
    _ -> int.to_float(completed + closed) /. int.to_float(total) *. 100.0
  }
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
    #("completion_pct", json.float(percent)),
  ])
}

pub fn create(
  workspace: String,
  title: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let now = time.now()
  let priority = parse_priority(rest)
  let labels = parse_labels(rest)
  let kind = parse_kind(rest)
  case parse_parent(rest) {
    option.Some(parent_id) ->
      case
        mnesia_store.current_store(workspace),
        mnesia_store.get_current(workspace, parent_id)
      {
        Ok(index), Ok(_) -> {
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
          let task = configure_gate(task, rest)
          mnesia_store.create(workspace, task) |> result_json
        }
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
      }
    option.None ->
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
      |> configure_gate(rest)
      |> mnesia_store.create(workspace, _)
      |> result_json
  }
}

fn configure_gate(task: Task, args: List(String)) -> Task {
  case task.kind {
    Gate ->
      builder.update(task, fn(current) {
        Task(
          ..current,
          gate_due: parse_gate_due(args),
          gate_satisfied: has_flag(args, "--satisfied"),
        )
      })
    _ -> task
  }
}

fn parse_gate_due(args: List(String)) -> option.Option(Int) {
  case args {
    ["--due", value, ..] ->
      case int.parse(value) {
        Ok(due) -> option.Some(due)
        Error(_) -> option.None
      }
    [_, ..rest] -> parse_gate_due(rest)
    [] -> option.None
  }
}

fn has_flag(args: List(String), flag: String) -> Bool {
  list.any(args, fn(argument) { argument == flag })
}

pub fn satisfy_gate(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(previous) {
    case previous.kind {
      Gate ->
        builder.update(previous, fn(task) {
          Task(..task, gate_satisfied: True, updated_at: time.now())
        })
        |> mnesia_store.replace(workspace, previous, _)
      _ -> Error("task is not a gate: " <> id)
    }
  })
  |> result_json
}

pub fn update(
  workspace: String,
  id: String,
  status: String,
) -> Result(json.Json, String) {
  case
    serde.status_from_string(status),
    mnesia_store.get_current(workspace, id)
  {
    Ok(new_status), Ok(previous) ->
      builder.update(previous, fn(t) {
        Task(..t, status: new_status, updated_at: time.now())
      })
      |> mnesia_store.replace(workspace, previous, _)
      |> result_json
    Error(_), _ -> Error("invalid status: " <> status)
    _, Error(error) -> Error(error)
  }
}

pub fn defer_until(
  workspace: String,
  id: String,
  until_text: String,
) -> Result(json.Json, String) {
  case int.parse(until_text), mnesia_store.get_current(workspace, id) {
    Ok(until), Ok(previous) ->
      builder.update(previous, fn(task) {
        Task(..task, defer_until: option.Some(until), updated_at: time.now())
      })
      |> mnesia_store.replace(workspace, previous, _)
      |> result_json
    Error(_), _ -> Error("defer timestamp must be an integer")
    _, Error(error) -> Error(error)
  }
}

pub fn close(
  workspace: String,
  id: String,
  reason: String,
) -> Result(json.Json, String) {
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(previous) {
    builder.update(previous, fn(task) {
      Task(
        ..task,
        status: Closed,
        closure_reason: option.Some(reason),
        updated_at: time.now(),
      )
    })
    |> mnesia_store.replace(workspace, previous, _)
  })
  |> result_json
}

pub fn add_label(
  workspace: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  case mnesia_store.get_current(workspace, id) {
    Ok(previous) ->
      builder.update(previous, fn(task) {
        case list.contains(task.labels, label) {
          True -> task
          False ->
            Task(..task, labels: [label, ..task.labels], updated_at: time.now())
        }
      })
      |> mnesia_store.replace(workspace, previous, _)
      |> result_json
    Error(error) -> Error(error)
  }
}

pub fn set_priority(
  workspace: String,
  id: String,
  priority_text: String,
) -> Result(json.Json, String) {
  case int.parse(priority_text), mnesia_store.get_current(workspace, id) {
    Ok(priority), Ok(previous) ->
      builder.update(previous, fn(task) {
        Task(..task, priority:, updated_at: time.now())
      })
      |> mnesia_store.replace(workspace, previous, _)
      |> result_json
    Error(_), _ -> Error("invalid priority: " <> priority_text)
    _, Error(error) -> Error(error)
  }
}

pub fn claim(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let assignee = case rest {
    [value, ..] -> value
    [] -> "agent"
  }
  case mnesia_store.get_current(workspace, id) {
    Ok(previous) ->
      case previous.status {
        Open ->
          builder.update(previous, fn(t) {
            Task(
              ..t,
              status: InProgress,
              assignee: option.Some(assignee),
              updated_at: time.now(),
            )
          })
          |> mnesia_store.replace(workspace, previous, _)
          |> result_json
        _ -> Error("task is not open: " <> id)
      }
    Error(error) -> Error(error)
  }
}

/// Deterministically claim the first ready task matching the optional label.
/// `graph.ready_tasks` supplies the stable ID order; `claim` then advances that
/// chosen head through Mnesia compare-and-swap. If another worker wins a race,
/// retry the remaining ready candidates rather than returning a stale task.
pub fn claim_next_ready(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let assignee_args = claim_assignee_args(rest)
  let label = parse_label_filter(rest)
  mnesia_store.current_store(workspace)
  |> result.try(fn(index) {
    index
    |> store.current_tasks()
    |> graph.ready_tasks_at(time.now())
    |> filter_by_label(label)
    |> claim_first_available(workspace, assignee_args)
  })
}

fn claim_first_available(
  tasks: List(Task),
  workspace: String,
  assignee_args: List(String),
) -> Result(json.Json, String) {
  case tasks {
    [] -> Error("no ready tasks available")
    [task, ..rest] ->
      case claim(workspace, task.id, assignee_args) {
        Ok(value) -> Ok(value)
        Error(_) -> claim_first_available(rest, workspace, assignee_args)
      }
  }
}

/// `ready --claim [assignee] [--label label]` carries both selector and
/// assignee flags. Keep the latter out of the label parser's concern.
fn claim_assignee_args(args: List(String)) -> List(String) {
  case args {
    ["--label", _, ..rest] -> claim_assignee_args(rest)
    [value, ..] -> [value]
    [] -> []
  }
}

/// Explicit duplicate consolidation. The caller must name both heads; semantic
/// candidate discovery never reaches this mutation. Every direct reference to
/// the source is redirected to the canonical task, then the source is closed
/// with durable provenance. The whole plan commits through one Mnesia CAS batch.
pub fn merge_duplicate(
  workspace: String,
  source_id: String,
  canonical_id: String,
) -> Result(json.Json, String) {
  case source_id == canonical_id {
    True -> Error("source and canonical task must differ")
    False ->
      current_tasks(workspace)
      |> result.try(fn(tasks) {
        case
          mnesia_store.get_current(workspace, source_id),
          mnesia_store.get_current(workspace, canonical_id)
        {
          Error(error), _ -> Error(error)
          _, Error(error) -> Error(error)
          Ok(source), Ok(_canonical) ->
            case
              source.status == Closed
              && source.closure_reason
              == option.Some("merged into " <> canonical_id)
            {
              True ->
                Ok(
                  json.object([
                    #("source", json.string(source_id)),
                    #("canonical", json.string(canonical_id)),
                    #("merged", json.bool(True)),
                    #("idempotent", json.bool(True)),
                  ]),
                )
              False -> {
                let rewritten =
                  rewrite_duplicate_plan(tasks, source, canonical_id)
                mnesia_store.replace_many(workspace, rewritten)
                |> result.map(fn(_) {
                  json.object([
                    #("source", json.string(source_id)),
                    #("canonical", json.string(canonical_id)),
                    #("merged", json.bool(True)),
                    #("idempotent", json.bool(False)),
                  ])
                })
              }
            }
        }
      })
  }
}

fn rewrite_duplicate_plan(
  tasks: List(Task),
  source: Task,
  canonical_id: String,
) -> List(#(Task, Task)) {
  tasks
  |> list.filter_map(fn(task) {
    let rewritten_relationships =
      task.relationships
      |> list.map(fn(relation) {
        case relation.target_id == source.id {
          True -> Relationship(canonical_id, relation.relation)
          False -> relation
        }
      })
    let rewritten_parent = case task.parent_id {
      option.Some(parent) if parent == source.id -> option.Some(canonical_id)
      other -> other
    }
    let updated = case task.id == source.id {
      True ->
        builder.update(task, fn(current) {
          Task(
            ..current,
            status: Closed,
            relationships: [
              Relationship(canonical_id, Supersedes),
              ..rewritten_relationships
            ],
            closure_reason: option.Some("merged into " <> canonical_id),
            updated_at: time.now(),
          )
        })
      False ->
        builder.update(task, fn(current) {
          Task(
            ..current,
            relationships: rewritten_relationships,
            parent_id: rewritten_parent,
            updated_at: time.now(),
          )
        })
    }
    case updated.content_hash == task.content_hash {
      True -> Error(Nil)
      False -> Ok(#(task, updated))
    }
  })
}

pub fn dependency_list(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  mnesia_store.get_current(workspace, id)
  |> result.map(fn(task) {
    json.array(task.relationships, of: fn(relation) {
      json.object([
        #("target_id", json.string(relation.target_id)),
        #("relation", json.string(relation_name(relation.relation))),
      ])
    })
  })
}

pub fn dependency_tree(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.map(fn(tasks) { dependency_tree_json(tasks, id, []) })
}

fn dependency_tree_json(
  tasks: List(Task),
  id: String,
  seen: List(String),
) -> json.Json {
  case list.contains(seen, id) {
    True -> json.object([#("id", json.string(id)), #("cycle", json.bool(True))])
    False ->
      case list.find(tasks, fn(task) { task.id == id }) {
        Error(_) ->
          json.object([#("id", json.string(id)), #("missing", json.bool(True))])
        Ok(task) ->
          json.object([
            #("id", json.string(id)),
            #("title", json.string(task.title)),
            #(
              "dependencies",
              json.array(task.relationships, of: fn(r) {
                json.object([
                  #("relation", json.string(relation_name(r.relation))),
                  #(
                    "node",
                    dependency_tree_json(tasks, r.target_id, [id, ..seen]),
                  ),
                ])
              }),
            ),
          ])
      }
  }
}

pub fn doctor(workspace: String) -> Result(json.Json, String) {
  case
    mnesia_store.current_store(workspace),
    mnesia_store.version_store(workspace)
  {
    Ok(current), Ok(versions) -> {
      let tasks = store.current_tasks(current)
      let cycles = graph.cycle_edges(tasks)
      let missing =
        list.flat_map(tasks, fn(task) {
          task.relationships
          |> list.filter_map(fn(r) {
            case
              list.any(tasks, fn(candidate) { candidate.id == r.target_id })
            {
              True -> Error(Nil)
              False -> Ok(task.id <> " -> " <> r.target_id)
            }
          })
        })
      Ok(
        json.object([
          #(
            "healthy",
            json.bool(list.is_empty(cycles) && list.is_empty(missing)),
          ),
          #("tasks", json.int(list.length(tasks))),
          #("versions", json.int(list.length(store.list(versions)))),
          #("cycles", json.int(list.length(cycles))),
          #("missing_targets", json.int(list.length(missing))),
          #("repair", json.string("none; diagnostics are read-only")),
        ]),
      )
    }
    Error(error), _ -> Error(error)
    _, Error(error) -> Error(error)
  }
}

fn relation_name(relation: types.RelationType) -> String {
  case relation {
    Blocks -> "blocks"
    RelatesTo -> "relates_to"
    Duplicates -> "duplicates"
    Supersedes -> "supersedes"
    ParentChild -> "parent_child"
    WaitsFor -> "waits_for"
    DiscoveredFrom -> "discovered_from"
    Tracks -> "tracks"
    CausedBy -> "caused_by"
    Validates -> "validates"
    ConditionalBlocks -> "conditional_blocks"
    RepliesTo -> "replies_to"
  }
}

pub fn add_dependency(
  workspace: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let relation = parse_relation_type(rest)
  case mnesia_store.current_store(workspace) {
    Error(error) -> Error(error)
    Ok(index) ->
      case
        mnesia_store.get_current(workspace, task_id),
        mnesia_store.get_current(workspace, target_id)
      {
        Error(error), _ -> Error(error)
        _, Error(error) -> Error(error)
        Ok(previous), Ok(_) ->
          case
            graph.would_cycle(graph.all_edges(store.current_tasks(index)), #(
              task_id,
              target_id,
            ))
          {
            True ->
              Error(
                "relation would create a cycle: "
                <> task_id
                <> " -> "
                <> target_id,
              )
            False ->
              apply.relation_typed(previous, target_id, relation, time.now())
              |> mnesia_store.replace(workspace, previous, _)
              |> result_json
          }
      }
  }
}

/// JSONL is an explicit interchange artifact. Exports include immutable history,
/// not only heads, preserving inspect/history and peer reconciliation semantics.
pub fn export_jsonl_to(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  mnesia_store.exportable_versions(workspace)
  |> result.try(fn(versions) {
    case jsonl.flush(store.list(versions), to: path) {
      Ok(_) -> Ok(json.string("exported immutable task history to " <> path))
      Error(_) -> Error("export failed: could not write " <> path)
    }
  })
}

pub fn export_jsonl(workspace: String) -> Result(json.Json, String) {
  export_jsonl_to(workspace, workspace <> "/tasks.jsonl")
}

pub fn backup_jsonl(workspace: String) -> Result(json.Json, String) {
  mnesia_store.exportable_versions(workspace)
  |> result.try(fn(versions) {
    let path = workspace <> "/tasks.jsonl.bak." <> int.to_string(time.now())
    case jsonl.flush(store.list(versions), to: path) {
      Ok(_) -> Ok(json.string("backed up Mnesia history to " <> path))
      Error(_) -> Error("backup failed: could not write " <> path)
    }
  })
}

/// Import and reconciliation are daemon operations. JSONL is validated before
/// Mnesia writes; a same-ID divergent current head is rejected, never replaced.
pub fn import_jsonl(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  jsonl.load(from: path)
  |> result.try(fn(tasks) {
    mnesia_store.import_snapshot(workspace, store.from_list(tasks))
  })
  |> result.map(fn(_) { json.string("imported JSONL snapshot from " <> path) })
}

pub fn reconcile_jsonl(
  workspace: String,
  path: String,
) -> Result(json.Json, String) {
  import_jsonl(workspace, path)
}

/// Pull a peer snapshot and import it through the transactional repository.
/// The TCP transport is deliberately read-only; only this daemon commits it.
pub fn pull_peer(
  workspace: String,
  host: String,
  port: Int,
) -> Result(json.Json, String) {
  sync_peer.fetch(host, port)
  |> result.try(fn(snapshot) {
    mnesia_store.import_replica_snapshot(
      workspace,
      store.from_list(snapshot.versions),
      snapshot.heads,
    )
  })
  |> result.map(fn(_) {
    json.string(
      "reconciled transactional store from "
      <> host
      <> ":"
      <> int.to_string(port),
    )
  })
}

fn result_json(result: Result(Task, String)) -> Result(json.Json, String) {
  case result {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(error) -> Error(error)
  }
}

fn filter_by_label(
  tasks: List(Task),
  label: option.Option(String),
) -> List(Task) {
  case label {
    option.Some(wanted) ->
      list.filter(tasks, fn(task) { list.contains(task.labels, wanted) })
    option.None -> tasks
  }
}

fn parse_label_filter(args: List(String)) -> option.Option(String) {
  case args {
    ["--label", label, ..] -> option.Some(label)
    [_first, ..rest] -> parse_label_filter(rest)
    [] -> option.None
  }
}

fn parse_parent(args: List(String)) -> option.Option(String) {
  case args {
    ["--parent", id, ..] -> option.Some(id)
    [_first, ..rest] -> parse_parent(rest)
    [] -> option.None
  }
}

fn parse_kind(args: List(String)) -> TaskKind {
  case args {
    ["--kind", value, ..] -> serde.kind_from_string(value)
    [_, ..rest] -> parse_kind(rest)
    [] -> DefaultTask
  }
}

fn parse_priority(args: List(String)) -> Int {
  case args {
    ["--priority", value, ..] ->
      case int.parse(value) {
        Ok(n) -> n
        Error(_) -> 0
      }
    [_first, ..rest] -> parse_priority(rest)
    [] -> 0
  }
}

fn parse_labels(args: List(String)) -> List(String) {
  case args {
    ["--label", label, ..rest] -> [label, ..parse_labels(rest)]
    [_first, ..rest] -> parse_labels(rest)
    [] -> []
  }
}

fn parse_relation_type(args: List(String)) {
  case args {
    ["--type", kind, ..] ->
      case serde.relation_from_string(kind) {
        Ok(t) -> t
        Error(_) -> Blocks
      }
    [_first, ..rest] -> parse_relation_type(rest)
    [] -> Blocks
  }
}

fn next_child_id(index: store.Store, parent_id: String) -> String {
  let prefix = parent_id <> "."
  let max_child =
    store.current_tasks(index)
    |> list.fold(0, fn(max, task) {
      case string.starts_with(task.id, prefix) {
        True ->
          case
            int.parse(string.slice(
              task.id,
              string.length(prefix),
              string.length(task.id),
            ))
          {
            Ok(n) -> int.max(max, n)
            Error(_) -> max
          }
        False -> max
      }
    })
  prefix <> int.to_string(max_child + 1)
}
