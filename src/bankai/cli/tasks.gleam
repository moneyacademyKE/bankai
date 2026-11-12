//// Local task commands: create, list, ready, count, blocked, cycles,
//// duplicates, stale, messages, dependencies, reclaim, remember, inspect.

import bankai/builder
import bankai/cli/parser
import bankai/graph
import bankai/lease
import bankai/memory
import bankai/message
import bankai/relations
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/task_view
import bankai/time
import bankai/types.{
  type Task, Blocks, Duplicates, InProgress, Open, ParentChild, Relationship,
  Task,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import simplifile

pub fn init_cmd(workspace: String) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  Ok(json.string("initialized bankai workspace at " <> workspace))
}

pub fn create_cmd(
  workspace: String,
  tasks_path: String,
  parsed: parser.CreateArgs,
  _raw_rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  let now = time.now()
  let parser.CreateArgs(
    title,
    description,
    labels,
    priority_text,
    parent,
    kind_text,
  ) = parsed
  use title <- result.try(parser.validate_title(title))
  let priority = case priority_text {
    option.Some(p) -> parser.parse_priority(["--priority", p])
    option.None -> 1
  }
  use priority <- result.try(parser.validate_priority(priority))
  let kind = case kind_text {
    option.Some(k) -> parser.parse_kind(["--kind", k])
    option.None -> types.DefaultTask
  }
  case parent {
    option.Some(parent_id) -> {
      use index <- result.try(jsonl.load_store(from: tasks_path))
      case store.find_by_id(index, parent_id) {
        Error(Nil) -> Error("no such parent task: " <> parent_id)
        Ok(_) -> {
          case
            graph.would_cycle_parent_chain(
              store.current_tasks(index),
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
                  description,
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
              use _ <- result.try(jsonl.flush_report(
                store.list(index),
                to: tasks_path,
              ))
              Ok(serde.task_to_json(task))
            }
          }
        }
      }
    }
    option.None -> {
      let task =
        builder.build_with_derived_id(
          title,
          description,
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
      use index <- result.try(jsonl.load_store(from: tasks_path))
      let index = store.put(index, task)
      use _ <- result.try(jsonl.flush_report(store.list(index), to: tasks_path))
      Ok(serde.task_to_json(task))
    }
  }
}

/// Same envelope as the daemon path (task_view) so scripts see ONE list
/// shape whether the daemon answered or this process read the store itself.
pub fn list_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  case task_view.parse(rest) {
    Error(e) -> Error(e)
    Ok(spec) -> {
      use tasks <- result.try(
        jsonl.load_store(from: tasks_path) |> result.map(store.current_tasks),
      )
      Ok(task_view.envelope(
        tasks,
        spec,
        time.now(),
        task_view.has_flag(rest, "--compact"),
      ))
    }
  }
}

pub fn ready_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  use tasks <- result.try(
    jsonl.load_store(from: tasks_path)
    |> result.map(store.current_tasks)
    |> result.map(graph.ready_tasks),
  )
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

pub fn count_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  use tasks <- result.try(
    jsonl.load_store(from: tasks_path) |> result.map(store.current_tasks),
  )
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.object([#("count", json.int(list.length(tasks)))]))
}

pub fn blocked_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  use tasks <- result.try(
    jsonl.load_store(from: tasks_path)
    |> result.map(store.current_tasks)
    |> result.map(fn(tasks) { graph.blocked_tasks_at(tasks, time.now()) }),
  )
  let tasks = filter_by_label(tasks, parser.parse_label_filter(rest))
  Ok(json.array(tasks, of: serde.task_to_json))
}

pub fn cycles_cmd(tasks_path: String) -> Result(json.Json, String) {
  use edges <- result.try(
    jsonl.load_store(from: tasks_path)
    |> result.map(store.current_tasks)
    |> result.map(graph.cycle_edges),
  )
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

pub fn duplicates_cmd(tasks_path: String) -> Result(json.Json, String) {
  use pairs <- result.try(
    jsonl.load_store(from: tasks_path)
    |> result.map(store.current_tasks)
    |> result.map(fn(tasks) {
      list.flat_map(tasks, fn(t) {
        t.relationships
        |> list.filter(fn(r) { r.relation == Duplicates })
        |> list.map(fn(r) { #(t.id, r.target_id) })
      })
    }),
  )
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

pub fn stale_cmd(
  tasks_path: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let days = parser.parse_days(rest)
  let cutoff = time.now() - days * time.day_ns
  use tasks <- result.try(
    jsonl.load_store(from: tasks_path)
    |> result.map(store.current_tasks)
    |> result.map(fn(tasks) {
      list.filter(tasks, fn(t) {
        graph.is_active(t.status) && t.updated_at < cutoff
      })
    }),
  )
  Ok(json.array(tasks, of: serde.task_to_json))
}

pub fn msg_add_cmd(
  workspace: String,
  tasks_path: String,
  task_id: String,
  text: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let _ = jsonl.ensure_dir(workspace)
  use index <- result.try(jsonl.load_store(from: tasks_path))
  case store.find_by_id(index, task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(_) -> {
      let parent = msg_add_parse_reply(rest)
      let msg = message.new(task_id, parent, "agent", text, time.now())
      let path = workspace <> "/messages.jsonl"
      use existing <- result.try(message.load(from: path))
      use _ <- result.try(
        message.flush([msg, ..existing], to: path)
        |> result.map_error(fn(e) {
          "could not write " <> path <> ": " <> simplifile.describe_error(e)
        }),
      )
      Ok(message.message_to_json(msg))
    }
  }
}

pub fn msg_list_cmd(
  workspace: String,
  task_id: String,
) -> Result(json.Json, String) {
  let path = workspace <> "/messages.jsonl"
  use msgs <- result.try(message.load(from: path))
  let task_msgs =
    msgs
    |> list.filter(fn(m) { m.task_id == task_id })
    |> list.sort(fn(a, b) { int.compare(b.ts, a.ts) })
  Ok(json.array(task_msgs, of: message.message_to_json))
}

pub fn dep_add_cmd(
  tasks_path: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let rel_type = parser.parse_relation_type(rest)
  use index <- result.try(jsonl.load_store(from: tasks_path))
  case store.find_by_id(index, task_id) {
    Error(Nil) -> Error("no such task: " <> task_id)
    Ok(task) ->
      case store.find_by_id(index, target_id) {
        Error(Nil) -> Error("no such task: " <> target_id)
        Ok(_) -> {
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
                relations.relation_typed(task, target_id, rel_type, time.now())
              let index = store.put(index, updated)
              use _ <- result.try(jsonl.flush_report(
                store.list(index),
                to: tasks_path,
              ))
              Ok(serde.task_to_json(updated))
            }
          }
        }
      }
  }
}

/// One update, one write (bk-57c1): the parsed grammar composes status,
/// claim, labels and priority in a single task rewrite instead of per-flag
/// arms that silently swallowed each other's args.
pub fn reclaim_cmd(tasks_path: String) -> Result(json.Json, String) {
  use index <- result.try(jsonl.load_store(from: tasks_path))
  let now = time.now()
  let expired =
    store.current_tasks(index)
    |> list.filter(fn(t) {
      t.status == InProgress && lease.is_expired(t.claim_lease_expires_at, now)
    })
  case expired {
    [] -> Ok(json.array([], of: json.string))
    _ -> {
      let expired_ids = list.map(expired, fn(t) { t.id })
      let updated_tasks =
        list.map(expired, fn(t) {
          builder.update(t, fn(x) {
            Task(
              ..x,
              status: Open,
              assignee: option.None,
              claim_lease_expires_at: option.None,
              updated_at: now,
            )
          })
        })
      let index =
        list.fold(updated_tasks, index, fn(acc, t) { store.put(acc, t) })
      use _ <- result.try(jsonl.flush_report(store.list(index), to: tasks_path))
      Ok(json.array(expired_ids, of: json.string))
    }
  }
}

pub fn remember_cmd(
  workspace: String,
  text: String,
) -> Result(json.Json, String) {
  memory.remember(workspace, text) |> result.map(memory.memory_to_json)
}

pub fn memories_cmd(workspace: String) -> Result(json.Json, String) {
  memory.all(workspace)
  |> result.map(fn(memories) { json.array(memories, of: memory.memory_to_json) })
}

pub fn inspect_cmd(
  tasks_path: String,
  hash: String,
) -> Result(json.Json, String) {
  use index <- result.try(jsonl.load_store(from: tasks_path))
  case store.get_by_hex(index, hash) {
    Ok(task) -> Ok(serde.task_to_json(task))
    Error(Nil) -> Error("no task for hash: " <> hash)
  }
}

pub fn msg_add_parse_reply(args: List(String)) -> String {
  case args {
    ["--reply", v, ..] -> v
    [_, ..rest] -> msg_add_parse_reply(rest)
    [] -> ""
  }
}

pub fn next_child_id(index: store.Store, parent_id: String) -> String {
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

pub fn filter_by_label(tasks: List(Task), label: Option(String)) -> List(Task) {
  case label {
    option.None -> tasks
    option.Some(l) -> list.filter(tasks, fn(t) { list.contains(t.labels, l) })
  }
}
