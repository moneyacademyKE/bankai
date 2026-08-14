import bankai/builder
import bankai/serde
import bankai/types.{
  type RelationType, type Task, Blocks, CausedBy, ConditionalBlocks,
  DiscoveredFrom, Duplicates, ParentChild, RelatesTo, RepliesTo, Supersedes,
  Task, Tracks, Validates, WaitsFor,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/set.{type Set}
import gleam/string

pub type Direction {
  Outgoing
  Incoming
  Both
}

pub type Query {
  Query(direction: Direction, relation: Option(RelationType), depth: Int)
}

pub type Edge {
  Edge(from: String, to: String, relation: RelationType)
}

pub fn query(args: List(String)) -> Result(Query, String) {
  parse(args, Query(Outgoing, option.None, 1))
}

fn parse(args: List(String), current: Query) -> Result(Query, String) {
  case args {
    [] -> Ok(current)
    ["--direction", value, ..rest] ->
      direction(value)
      |> result.try(fn(value) {
        parse(rest, Query(..current, direction: value))
      })
    ["--type", value, ..rest] ->
      serde.relation_from_string(value)
      |> result.map_error(fn(_) { "invalid relation type: " <> value })
      |> result.try(fn(value) {
        parse(rest, Query(..current, relation: option.Some(value)))
      })
    ["--depth", value, ..rest] ->
      case int.parse(value) {
        Ok(depth) ->
          case depth >= 0 {
            True -> parse(rest, Query(..current, depth: depth))
            False -> Error("depth must be non-negative")
          }
        Error(_) -> Error("depth must be an integer")
      }
    [unknown, ..] -> Error("unknown relation option: " <> unknown)
  }
}

fn direction(value: String) -> Result(Direction, String) {
  case value {
    "outgoing" -> Ok(Outgoing)
    "incoming" -> Ok(Incoming)
    "both" -> Ok(Both)
    _ -> Error("invalid direction: " <> value)
  }
}

pub fn relation_typed(
  task: Task,
  target_id: String,
  relation: RelationType,
  now: Int,
) -> Task {
  add_typed(task, target_id, relation, now)
}

pub fn add_typed(
  task: Task,
  target_id: String,
  relation: RelationType,
  now: Int,
) -> Task {
  let edge = types.Relationship(target_id: target_id, relation: relation)
  case list.contains(task.relationships, edge) {
    True -> task
    False -> {
      let relationships = [edge, ..task.relationships]
      builder.update(task, fn(current) {
        Task(..current, relationships: relationships, updated_at: now)
      })
    }
  }
}

pub fn add(
  task: Task,
  target_id: String,
  relation: RelationType,
  all_edges: List(#(String, String)),
  now: Int,
) -> Result(Task, String) {
  let is_blocking = case relation {
    Blocks | WaitsFor | ConditionalBlocks -> True
    _ -> False
  }
  case is_blocking {
    True ->
      case list.contains(all_edges, #(target_id, task.id)) {
        True -> Error("adding relation creates a dependency cycle")
        False -> Ok(add_typed(task, target_id, relation, now))
      }
    False -> Ok(add_typed(task, target_id, relation, now))
  }
}

pub fn remove(
  task: Task,
  target_id: String,
  relation: RelationType,
  now: Int,
) -> Task {
  let relationships =
    task.relationships
    |> list.filter(fn(edge) {
      !{ edge.target_id == target_id && edge.relation == relation }
    })
  case relationships == task.relationships {
    True -> task
    False ->
      builder.update(task, fn(current) {
        Task(..current, relationships: relationships, updated_at: now)
      })
  }
}

pub fn edges(tasks: List(Task), relation: Option(RelationType)) -> List(Edge) {
  tasks
  |> list.flat_map(fn(task) {
    task.relationships
    |> list.filter(fn(edge) {
      case relation {
        option.None -> True
        option.Some(wanted) -> edge.relation == wanted
      }
    })
    |> list.map(fn(edge) { Edge(task.id, edge.target_id, edge.relation) })
  })
  |> list.sort(by: compare_edges)
}

pub fn traverse(tasks: List(Task), start: String, query: Query) -> List(Edge) {
  walk(edges(tasks, query.relation), [#(start, 0)], query, set.new(), [])
  |> list.reverse
}

fn walk(
  graph: List(Edge),
  pending: List(#(String, Int)),
  query: Query,
  seen: Set(String),
  found: List(Edge),
) -> List(Edge) {
  case pending {
    [] -> found
    [#(node, level), ..rest] ->
      case level >= query.depth || set.contains(seen, node) {
        True -> walk(graph, rest, query, seen, found)
        False -> {
          let selected = adjacent(graph, node, query.direction)
          let next =
            selected
            |> list.map(fn(edge) { #(next_node(edge, node), level + 1) })
            |> list.append(rest)
          walk(
            graph,
            next,
            query,
            set.insert(seen, node),
            append_unique(selected, found),
          )
        }
      }
  }
}

fn adjacent(
  graph: List(Edge),
  node: String,
  direction: Direction,
) -> List(Edge) {
  graph
  |> list.filter(fn(edge) {
    case direction {
      Outgoing -> edge.from == node
      Incoming -> edge.to == node
      Both -> edge.from == node || edge.to == node
    }
  })
}

fn next_node(edge: Edge, current: String) -> String {
  case edge.from == current {
    True -> edge.to
    False -> edge.from
  }
}

fn append_unique(new: List(Edge), found: List(Edge)) -> List(Edge) {
  list.fold(new, found, fn(acc, edge) {
    case list.contains(acc, edge) {
      True -> acc
      False -> [edge, ..acc]
    }
  })
}

pub fn graph_json(
  tasks: List(Task),
  args: List(String),
) -> Result(json.Json, String) {
  query(args)
  |> result.map(fn(query) {
    json.object([
      #("nodes", json.array(tasks, of: node_json)),
      #("edges", json.array(edges(tasks, query.relation), of: edge_json)),
    ])
  })
}

pub fn traversal_json(
  tasks: List(Task),
  start: String,
  args: List(String),
) -> Result(json.Json, String) {
  query(args)
  |> result.map(fn(query) {
    json.object([
      #("start", json.string(start)),
      #("edges", json.array(traverse(tasks, start, query), of: edge_json)),
    ])
  })
}

pub fn integrity_json(
  tasks: List(Task),
  cycles: List(#(String, String)),
) -> json.Json {
  let ids = list.map(tasks, fn(task) { task.id })
  let missing =
    edges(tasks, option.None)
    |> list.filter(fn(edge) { !list.contains(ids, edge.to) })
  let duplicate_edges = duplicate_edges(edges(tasks, option.None))
  json.object([
    #(
      "healthy",
      json.bool(
        list.is_empty(missing)
        && list.is_empty(cycles)
        && list.is_empty(duplicate_edges),
      ),
    ),
    #("missing_targets", json.array(missing, of: edge_json)),
    #(
      "blocking_cycles",
      json.array(cycles, of: fn(cycle) {
        json.object([
          #("from", json.string(cycle.0)),
          #("to", json.string(cycle.1)),
        ])
      }),
    ),
    #("duplicate_edges", json.array(duplicate_edges, of: edge_json)),
  ])
}

fn duplicate_edges(all: List(Edge)) -> List(Edge) {
  all
  |> list.filter(fn(edge) {
    all |> list.filter(fn(candidate) { candidate == edge }) |> list.length() > 1
  })
  |> list.unique
}

fn node_json(task: Task) -> json.Json {
  json.object([
    #("id", json.string(task.id)),
    #("title", json.string(task.title)),
  ])
}

fn edge_json(edge: Edge) -> json.Json {
  json.object([
    #("from", json.string(edge.from)),
    #("to", json.string(edge.to)),
    #("relation", json.string(relation_name(edge.relation))),
  ])
}

pub fn relation_name(relation: RelationType) -> String {
  case relation {
    Blocks -> "blocks"
    RelatesTo -> "relates_to"
    Duplicates -> "duplicates"
    Supersedes -> "supersedes"
    RepliesTo -> "replies_to"
    ParentChild -> "parent_child"
    WaitsFor -> "waits_for"
    DiscoveredFrom -> "discovered_from"
    Tracks -> "tracks"
    CausedBy -> "caused_by"
    Validates -> "validates"
    ConditionalBlocks -> "conditional_blocks"
  }
}

fn compare_edges(a: Edge, b: Edge) {
  string.compare(
    a.from <> "|" <> a.to <> "|" <> relation_name(a.relation),
    b.from <> "|" <> b.to <> "|" <> relation_name(b.relation),
  )
}
