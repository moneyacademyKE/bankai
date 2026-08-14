//// Task creation and mutation service.
////
//// Coordinates atomic single-task mutations, gate configuration, cluster-fenced updates,
//// and duplicate merging in Mnesia.

import bankai/builder
import bankai/claimant
import bankai/cluster
import bankai/gates/service as gate_service
import bankai/graph
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/task_lifecycle
import bankai/time
import bankai/types.{
  type Task, type TaskKind, Closed, DefaultTask, Gate, InProgress, Open,
  ParentChild, Relationship, Supersedes, Task, Wisp,
}
import bankai/wisps/service as wisp_service
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

pub type Claimed {
  Claimed(task: Task, admission: option.Option(cluster.Admission))
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
          create_task(workspace, task, rest)
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
      |> create_task(workspace, _, rest)
  }
}

fn create_task(
  workspace: String,
  task: Task,
  args: List(String),
) -> Result(json.Json, String) {
  case task.kind {
    Wisp ->
      wisp_service.create(workspace, task, args)
      |> result.map(serde.task_to_json)
    _ -> mnesia_store.create(workspace, task) |> result.map(serde.task_to_json)
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
  gate_service.resolve(workspace, id, ["--reason", "compatibility satisfy"])
}

pub fn update(
  workspace: String,
  id: String,
  status: String,
) -> Result(json.Json, String) {
  case cluster.mode(workspace) {
    Error(error) -> Error(error)
    Ok(cluster.Local) -> update_local(workspace, id, status)
    Ok(cluster.Cluster(_, _)) ->
      Error("clustered claimant transitions require --fence <token>")
  }
}

fn update_local(
  workspace: String,
  id: String,
  status: String,
) -> Result(json.Json, String) {
  case
    serde.status_from_string(status),
    mnesia_store.get_current(workspace, id)
  {
    Ok(new_status), Ok(previous) ->
      builder.update(previous, fn(task) {
        Task(..task, status: new_status, updated_at: time.now())
      })
      |> mnesia_store.replace(workspace, previous, _)
      |> result.map(serde.task_to_json)
    Error(_), _ -> Error("invalid status: " <> status)
    _, Error(error) -> Error(error)
  }
}

pub fn release(workspace: String, id: String) -> Result(json.Json, String) {
  task_lifecycle.release(workspace, id)
}

pub fn reopen(workspace: String, id: String) -> Result(json.Json, String) {
  task_lifecycle.reopen(workspace, id)
}

pub fn undefer(workspace: String, id: String) -> Result(json.Json, String) {
  task_lifecycle.undefer(workspace, id)
}

pub fn remove_label(
  workspace: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  task_lifecycle.remove_label(workspace, id, label)
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
      |> result.map(serde.task_to_json)
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
  |> result.map(serde.task_to_json)
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
      |> result.map(serde.task_to_json)
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
      |> result.map(serde.task_to_json)
    Error(_), _ -> Error("invalid priority: " <> priority_text)
    _, Error(error) -> Error(error)
  }
}

pub fn claim_next_ready(
  workspace: String,
  rest: List(String),
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.try(fn(tasks) {
    let now = time.now()
    gate_service.readiness_tasks(workspace, tasks, now)
    |> result.try(fn(readiness_tasks) {
      let ready =
        graph.ready_tasks_at(readiness_tasks, now)
        |> list.filter(fn(t) { t.kind != Wisp })
      let filtered = case parse_label_filter(rest) {
        option.None -> ready
        option.Some(label) ->
          list.filter(ready, fn(t) { list.contains(t.labels, label) })
      }
      case filtered {
        [first, ..] -> claim(workspace, first.id, parse_claimant(rest))
        [] -> Error("no ready tasks to claim")
      }
    })
  })
}

fn parse_claimant(args: List(String)) -> List(String) {
  case args {
    ["--label", _, ..rest] -> parse_claimant(rest)
    [other, ..rest] -> [other, ..parse_claimant(rest)]
    [] -> []
  }
}

fn parse_label_filter(args: List(String)) -> option.Option(String) {
  case args {
    ["--label", label, ..] -> option.Some(label)
    [_, ..rest] -> parse_label_filter(rest)
    [] -> option.None
  }
}

pub fn claim(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  claim_record(workspace, id, rest)
  |> result.map(claimed_json)
}

pub fn claim_record(
  workspace: String,
  id: String,
  rest: List(String),
) -> Result(Claimed, String) {
  let assignee = claimant.parse(rest)
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(previous) {
    case previous.status {
      Open ->
        builder.update(previous, fn(task) {
          Task(
            ..task,
            status: InProgress,
            assignee: option.Some(assignee),
            updated_at: time.now(),
          )
        })
        |> claim_admitted(workspace, previous, assignee, _)
      _ -> Error("task is not open: " <> id)
    }
  })
}

pub fn claimed_json(claimed: Claimed) -> json.Json {
  let Claimed(task, admission) = claimed
  case admission {
    option.None -> serde.task_to_json(task)
    option.Some(cluster.Admission(fence, commit_index, idempotent, command_id)) ->
      json.object([
        #("task", serde.task_to_json(task)),
        #("clustered", json.bool(True)),
        #("fence", json.int(fence)),
        #("commit_index", json.int(commit_index)),
        #("idempotent", json.bool(idempotent)),
        #("command_id", json.string(command_id)),
      ])
  }
}

pub fn update_fenced(
  workspace: String,
  id: String,
  status: String,
  fence_text: String,
) -> Result(json.Json, String) {
  case int.parse(fence_text), serde.status_from_string(status) {
    Ok(fence), Ok(next_status) ->
      mnesia_store.get_current(workspace, id)
      |> result.try(fn(previous) {
        builder.update(previous, fn(task) {
          Task(..task, status: next_status, updated_at: time.now())
        })
        |> fenced_replace(workspace, previous, fence, _)
      })
      |> result.map(serde.task_to_json)
    Error(_), _ -> Error("fence must be an integer")
    _, Error(_) -> Error("invalid status: " <> status)
  }
}

fn claim_admitted(
  workspace: String,
  previous: Task,
  assignee: String,
  updated: Task,
) -> Result(Claimed, String) {
  case cluster.mode(workspace) {
    Error(error) -> Error(error)
    Ok(cluster.Local) ->
      mnesia_store.replace(workspace, previous, updated)
      |> result.map(fn(task) { Claimed(task, option.None) })
    Ok(cluster.Cluster(_, _)) ->
      cluster.claim(
        workspace,
        previous.id,
        assignee,
        hash_text(previous),
        hash_text(updated),
        time.now(),
      )
      |> result.try(fn(admission) {
        let cluster.Admission(_, _, _, command_id) = admission
        mnesia_store.replace_committed(workspace, command_id, previous, updated)
        |> result.map(fn(task) { Claimed(task, option.Some(admission)) })
      })
  }
}

fn fenced_replace(
  workspace: String,
  previous: Task,
  fence: Int,
  updated: Task,
) -> Result(Task, String) {
  case cluster.mode(workspace) {
    Error(error) -> Error(error)
    Ok(cluster.Local) ->
      Error("fenced updates require a clustered Bankai profile")
    Ok(cluster.Cluster(_, _)) ->
      cluster.transition(
        workspace,
        previous.id,
        hash_text(previous),
        hash_text(updated),
        fence,
        time.now(),
      )
      |> result.try(fn(admission) {
        let cluster.Admission(_, _, _, command_id) = admission
        mnesia_store.replace_committed(workspace, command_id, previous, updated)
      })
  }
}

pub fn merge(
  workspace: String,
  source_id: String,
  canonical_id: String,
) -> Result(json.Json, String) {
  case source_id == canonical_id {
    True -> Error("source and canonical task must differ")
    False ->
      mnesia_store.current_store(workspace)
      |> result.map(store.current_tasks)
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

fn hash_text(task: Task) -> String {
  store.hash_key(task.content_hash)
}

fn next_child_id(index: store.Store, parent_id: String) -> String {
  let prefix = parent_id <> "."
  let child_suffixes =
    store.list(index)
    |> list.filter_map(fn(task) {
      case string.starts_with(task.id, prefix) {
        True -> {
          let suffix = string.drop_start(task.id, string.length(prefix))
          case int.parse(suffix) {
            Ok(n) -> Ok(n)
            Error(Nil) -> Error(Nil)
          }
        }
        False -> Error(Nil)
      }
    })
  let next = case list.reduce(child_suffixes, int.max) {
    Ok(highest) -> highest + 1
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

fn parse_parent(args: List(String)) -> option.Option(String) {
  case args {
    [] -> option.None
    ["--parent", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_parent(rest)
  }
}

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

fn parse_priority(args: List(String)) -> Int {
  case args {
    ["--priority", value, ..] ->
      case int.parse(value) {
        Ok(priority) -> priority
        Error(_) -> 1
      }
    [_, ..rest] -> parse_priority(rest)
    [] -> 1
  }
}
