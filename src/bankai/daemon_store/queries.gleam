//// Task read-only queries, search, analytics, and projections.
////
//// Queries derived state from Mnesia and AaronDB projections.

import bankai/aarondb_bridge
import bankai/cli
import bankai/gates/service as gate_service
import bankai/graph
import bankai/memory
import bankai/mnesia_store
import bankai/projections
import bankai/serde
import bankai/storage/store
import bankai/task_view
import bankai/time
import bankai/types.{
  type Task, Blocked, Closed, Completed, Duplicates, InProgress, Open,
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
  current_tasks(workspace)
  |> result.try(fn(tasks) {
    task_view.parse(rest)
    |> result.map(fn(spec) {
      task_view.envelope(
        tasks,
        spec,
        time.now(),
        task_view.has_flag(rest, "--compact"),
      )
    })
  })
}

pub fn ready_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.try(fn(tasks) {
    let now = time.now()
    gate_service.readiness_tasks(workspace, tasks, now)
    |> result.try(fn(readiness_tasks) {
      task_view.parse(rest)
      |> result.map(fn(spec) {
        case task_view.has_flag(rest, "--explain") {
          True -> {
            let candidates =
              task_view.apply(readiness_tasks, spec, now)
              |> list.filter(fn(task) { task.kind != types.Wisp })
            json.object([
              #(
                "explanations",
                json.array(candidates, of: fn(task) {
                  graph.readiness_explanation(task, readiness_tasks, now)
                }),
              ),
              #("total", json.int(list.length(candidates))),
            ])
          }
          False ->
            task_view.envelope(
              graph.ready_tasks_at(readiness_tasks, now)
                |> list.filter(fn(task) { task.kind != types.Wisp }),
              spec,
              now,
              task_view.has_flag(rest, "--compact"),
            )
        }
      })
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
  |> result.try(fn(tasks) {
    task_view.parse(rest)
    |> result.map(fn(spec) { task_view.count(tasks, spec, time.now()) })
  })
}

pub fn blocked_tasks(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  current_tasks(workspace)
  |> result.try(fn(tasks) {
    task_view.parse(rest)
    |> result.map(fn(spec) {
      task_view.envelope(
        list.filter(tasks, fn(task) { task.status == Blocked }),
        spec,
        time.now(),
        task_view.has_flag(rest, "--compact"),
      )
    })
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
  let cutoff = time.now() - parse_days(rest) * time.day_ns
  current_tasks(workspace)
  |> result.map(fn(tasks) {
    tasks
    |> list.filter(fn(task) {
      task.kind != types.Wisp
      && graph.is_active(task.status)
      && task.updated_at < cutoff
    })
    |> json.array(of: serde.task_to_json)
  })
}

pub fn history(workspace: String, id: String) -> Result(json.Json, String) {
  projection_gate(workspace)
  |> result.try(fn(_) { mnesia_store.version_store(workspace) })
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
  projected_tasks(workspace)
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
  projected_tasks(workspace)
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
  projected_snapshot(workspace)
  |> result.try(fn(snapshot) {
    let #(offset, tasks) = snapshot
    let docs = task_documents(tasks)
    tasks
    |> list.try_map(fn(task) {
      vector_bridge.projected_search(
        workspace,
        offset,
        docs,
        task.title <> " " <> task.description,
        parse_threshold(rest, 0.78),
        6,
      )
      |> result.map(fn(matches) {
        matches
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
    })
    |> result.map(list.flatten)
    |> result.map(fn(matches) { json.array(matches, of: fn(value) { value }) })
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
  projected_snapshot(workspace)
  |> result.try(fn(snapshot) {
    let #(offset, tasks) = snapshot
    let task_docs = task_documents(tasks)
    let memory_docs = memory_documents(workspace)
    let all_docs = list.append(task_docs, memory_docs)
    vector_bridge.projected_search(workspace, offset, all_docs, query, 0.18, 12)
    |> result.map(fn(matches) {
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

fn current_tasks(workspace: String) -> Result(List(Task), String) {
  mnesia_store.current_store(workspace) |> result.map(store.current_tasks)
}

fn projected_tasks(workspace: String) -> Result(List(Task), String) {
  projection_gate(workspace)
  |> result.try(fn(_) { current_tasks(workspace) })
}

fn projected_snapshot(workspace: String) -> Result(#(Int, List(Task)), String) {
  projection_gate(workspace)
  |> result.try(fn(_) { mnesia_store.projection_snapshot_rows(workspace) })
}

fn projection_gate(workspace: String) -> Result(Nil, String) {
  case projections.ensure_runtime(workspace) {
    Ok(_) ->
      case projections.runtime_status(workspace) {
        Ok(status) -> projection_status_gate(status)
        Error(_) -> bootstrap_projection_gate(workspace)
      }
    Error(_) -> bootstrap_projection_gate(workspace)
  }
}

fn projection_status_gate(
  status: projections.RuntimeStatus,
) -> Result(Nil, String) {
  let projections.RuntimeStatus(healthy, _, _, _, _, _, _, _, _, _, _, _, _, _) =
    status
  case healthy {
    True -> Ok(Nil)
    False -> Error("aarondb projection is unhealthy; Mnesia fallback required")
  }
}

fn bootstrap_projection_gate(workspace: String) -> Result(Nil, String) {
  projections.bootstrap(workspace)
  |> result.try(fn(view) {
    case projections.healthy(view) {
      True -> Ok(Nil)
      False ->
        Error("aarondb projection is unhealthy; Mnesia fallback required")
    }
  })
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

fn memory_docs(workspace: String) -> List(#(String, String, String)) {
  case memory.load(from: workspace <> "/memories.jsonl") {
    Ok(memories) ->
      list.map(memories, fn(memory) {
        #("memory", store.hash_key(memory.content_hash), memory.text)
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

fn parse_days(args: List(String)) -> Int {
  case args {
    ["--days", value, ..] ->
      case int.parse(value) {
        Ok(days) -> days
        Error(_) -> 30
      }
    [_, ..rest] -> parse_days(rest)
    [] -> 30
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
  dict.to_list(counts)
  |> list.map(fn(pair) {
    let #(status, count) = pair
    #(status, json.int(count))
  })
  |> json.object
}
