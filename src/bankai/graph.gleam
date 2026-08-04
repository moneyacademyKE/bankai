//// The task dependency graph — pure functions, no AST evaluation.
////
//// SEMANTICS (documented once, used everywhere):
////   A `Blocks` relationship `Relationship(target, Blocks)` on task T means
////   "T is blocked by target" — i.e. target must be Completed before T can be
////   ready. This keeps dependency info local to the dependent task.
////
//// A dependency edge is therefore (dependent -> dependency):
////   edge (a, b)  ==  "a depends on b"  ==  "a is blocked by b".
////
//// Per ADR-0001 amendment these are bankai's own small pure functions over the
//// task DAG (cycle_detect / topological_sort are trivial here; aarondb's graph
//// module is coupled to its internal index and drags a web-framework dep tree).

import bankai/types.{type Task, type TaskStatus, Blocks, Closed, Completed}
import gleam/list
import gleam/set.{type Set}
import gleam/string

/// Dependency edges (dependent -> dependency) for one task's Blocks relations.
pub fn dependency_edges(task: Task) -> List(#(String, String)) {
  task.relationships
  |> list.filter(fn(r) { r.relation == Blocks })
  |> list.map(fn(r) { #(task.id, r.target_id) })
}

/// All dependency edges across a set of tasks.
pub fn all_edges(tasks: List(Task)) -> List(#(String, String)) {
  list.flat_map(tasks, dependency_edges)
}

/// Edges that participate in a dependency cycle (the `cycles` query). An edge
/// (a -> b) — "a depends on b" — is on a cycle iff the dependency b can already
/// reach the dependent a (b -> ... -> a). Pure over the task DAG; self-loops
/// count. Only Blocks relations can cycle (they are the only directional edges),
/// which is why `all_edges` filters to Blocks.
pub fn cycle_edges(tasks: List(Task)) -> List(#(String, String)) {
  let edges = all_edges(tasks)
  edges
  |> list.filter(fn(e) {
    let #(from, to) = e
    reaches(edges, to, from)
  })
}

/// Would adding edge `proposed = #(dependent, dependency)` to `edges` create a
/// cycle? Yes iff the dependency can already reach the dependent (closing the
/// loop), or it's a self-loop. Used to gate `AddRelation`.
pub fn would_cycle(
  edges: List(#(String, String)),
  proposed: #(String, String),
) -> Bool {
  let #(from, to) = proposed
  case from == to {
    True -> True
    False -> reaches(edges, to, from)
  }
}

/// All dependency edges for a task plus a proposed new Blocks relationship,
/// without mutating the task. Used by the actor to validate before applying.
pub fn edges_with(
  task: Task,
  proposed_target: String,
) -> List(#(String, String)) {
  let proposed = #(task.id, proposed_target)
  [proposed, ..dependency_edges(task)]
}

/// A task is ready iff it is active (not Completed/Closed) AND every task it is
/// blocked by is Completed. Unknown/missing blockers count as blocking.
pub fn is_ready(task: Task, done: Set(String)) -> Bool {
  is_active(task.status)
  && list.all(task.relationships, fn(r) {
    case r.relation {
      Blocks -> set.contains(done, r.target_id)
      _ -> True
    }
  })
}

/// All currently-ready tasks. Plain function — NOT a gleamunison eval.
pub fn ready_tasks(tasks: List(Task)) -> List(Task) {
  let done = satisfied_ids(tasks)
  tasks
  |> list.filter(fn(t) { is_ready(t, done) })
  |> list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
}

/// Topological order of task ids: dependencies before dependents.
/// Best-effort if a cycle is present (remaining ids appended, sorted).
pub fn topological_sort(tasks: List(Task)) -> List(String) {
  let ids = tasks |> list.map(fn(t) { t.id })
  let edges = all_edges(tasks)
  do_topo(edges, ids, [])
}

// --- internals ---

fn reaches(
  edges: List(#(String, String)),
  start: String,
  target: String,
) -> Bool {
  walk(edges, [start], set.new(), target)
}

fn walk(
  edges: List(#(String, String)),
  stack: List(String),
  visited: Set(String),
  target: String,
) -> Bool {
  case stack {
    [] -> False
    [node, ..rest] ->
      case node == target {
        True -> True
        False ->
          case set.contains(visited, node) {
            True -> walk(edges, rest, visited, target)
            False -> {
              let visited = set.insert(visited, node)
              let next = list.append(neighbors(edges, node), rest)
              walk(edges, next, visited, target)
            }
          }
      }
  }
}

fn neighbors(edges: List(#(String, String)), node: String) -> List(String) {
  edges
  |> list.filter_map(fn(e) {
    let #(a, b) = e
    case a == node {
      True -> Ok(b)
      False -> Error(Nil)
    }
  })
}

/// Is this status "active" (work that still bears on readiness — not done and
/// not abandoned)? Pub so the CLI's `stale` drift filter reuses the single
/// definition of "active" instead of re-deriving it.
pub fn is_active(status: TaskStatus) -> Bool {
  case status {
    Completed -> False
    Closed -> False
    _ -> True
  }
}

// BUG-03 fix: a Blocks dependency is satisfied ONLY by Completed work — NOT by
// Closed. "Closed" = abandoned/won't-do: the dependency was not delivered, so
// the dependent stays blocked (NOT auto-ready). (was `completed_ids`, which
// wrongly included Closed via `!is_active`.)
fn satisfied_ids(tasks: List(Task)) -> Set(String) {
  tasks
  |> list.filter(fn(t) { t.status == Completed })
  |> list.map(fn(t) { t.id })
  |> set.from_list()
}

fn do_topo(
  edges: List(#(String, String)),
  remaining: List(String),
  acc: List(String),
) -> List(String) {
  case remaining {
    [] -> acc
    _ -> {
      let emitted =
        remaining
        |> list.filter(fn(id) {
          // emit id when all its dependencies (neighbors) are already in acc
          neighbors(edges, id)
          |> list.all(fn(dep) { list.contains(acc, dep) })
        })
        |> list.sort(by: string.compare)

      case emitted {
        [] ->
          // cycle: emit the rest deterministically
          list.reverse(acc)
          |> list.append(list.sort(remaining, by: string.compare))
        _ -> {
          let acc = list.append(acc, emitted)
          let remaining =
            remaining |> list.filter(fn(id) { !list.contains(emitted, id) })
          do_topo(edges, remaining, acc)
        }
      }
    }
  }
}
