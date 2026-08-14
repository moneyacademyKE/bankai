//// Task relationship and dependency graph service.
////
//// Manages typed dependencies, cycle prevention, traversal, and integrity auditing.

import bankai/graph
import bankai/mnesia_store
import bankai/relations
import bankai/serde
import bankai/storage/store
import bankai/time
import bankai/types.{type RelationType, type Task, Blocks}
import gleam/json
import gleam/list
import gleam/result

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
        Ok(previous), Ok(_) -> {
          let cycle =
            graph.is_blocking_relation(relation)
            && graph.would_cycle(graph.all_edges(store.current_tasks(index)), #(
              task_id,
              target_id,
            ))
          case cycle {
            True ->
              Error(
                "relation would create a cycle: "
                <> task_id
                <> " -> "
                <> target_id,
              )
            False ->
              relations.relation_typed(
                previous,
                target_id,
                relation,
                time.now(),
              )
              |> mnesia_store.replace(workspace, previous, _)
              |> result.map(serde.task_to_json)
          }
        }
      }
  }
}

pub fn remove_dependency(
  workspace: String,
  task_id: String,
  target_id: String,
  rest: List(String),
) -> Result(json.Json, String) {
  let relation = parse_relation_type(rest)
  mnesia_store.get_current(workspace, task_id)
  |> result.try(fn(previous) {
    let updated = relations.remove(previous, target_id, relation, time.now())
    case updated.content_hash == previous.content_hash {
      True -> Ok(previous)
      False -> mnesia_store.replace(workspace, previous, updated)
    }
  })
  |> result.map(serde.task_to_json)
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
        #("relation", json.string(relations.relation_name(relation.relation))),
      ])
    })
  })
}

pub fn dependency_tree(
  workspace: String,
  id: String,
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.map(fn(tasks) { dependency_tree_json(tasks, id, []) })
}

pub fn traverse_dependencies(
  workspace: String,
  id: String,
  args: List(String),
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.try(fn(tasks) {
    case list.any(tasks, fn(task) { task.id == id }) {
      False -> Error("no current task: " <> id)
      True -> relations.traversal_json(tasks, id, args)
    }
  })
}

pub fn dependency_graph(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.try(fn(tasks) { relations.graph_json(tasks, args) })
}

pub fn dependency_integrity(workspace: String) -> Result(json.Json, String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
  |> result.map(fn(tasks) {
    relations.integrity_json(tasks, graph.cycle_edges(tasks))
  })
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
                  #(
                    "relation",
                    json.string(relations.relation_name(r.relation)),
                  ),
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

fn parse_relation_type(args: List(String)) -> RelationType {
  case args {
    ["--type", value, ..] ->
      case serde.relation_from_string(value) {
        Ok(t) -> t
        Error(_) -> Blocks
      }
    [_, ..rest] -> parse_relation_type(rest)
    [] -> Blocks
  }
}
