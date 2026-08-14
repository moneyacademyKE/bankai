//// The task dependency graph — pure functions, no AST evaluation.
////
//// SEMANTICS (documented once, used everywhere):
////   A blocking relationship `Relationship(target, relation)` on task T means
////   "T cannot proceed until target is satisfied" — ordinary work is satisfied
////   only by Completed; a Gate is satisfied by a local manual, due-timer, or
////   already-verified signed fact. ParentChild establishes hierarchy but does NOT
////   block readiness. All other relation types (RelatesTo, Duplicates, Supersedes,
////   RepliesTo, DiscoveredFrom, Tracks, CausedBy, Validates) are informational.
////
//// READINESS POLICY:
////   Blocks, WaitsFor, ConditionalBlocks → target must be satisfied as above.
////   Gates are satisfaction facts and never appear as executable ready work.
////   Wisps are scratch state and also never appear as executable ready work.
////   ParentChild and all other relation types → informational only.
////
//// CYCLE DETECTION:
////   Blocks/WaitsFor/ConditionalBlocks edges are cycle-checked in the dep graph.
////   ParentChild is cycle-checked through the parent_id chain (hierarchy cycles).
////   Informational relations are not cycle-checked.
////
//// Per ADR-0001 amendment these are bankai's own small pure functions over the
//// task DAG (cycle_detect / topological_sort are trivial here; aarondb's graph
//// module is coupled to its internal index and drags a web-framework dep tree).

import bankai/types.{
  type Task, type TaskStatus, Blocked, Blocks, Closed, Completed,
  ConditionalBlocks, Gate, InProgress, Open, WaitsFor,
}
import gleam/json
import gleam/list
import gleam/option
import gleam/set.{type Set}
import gleam/string

/// Dependency edges (dependent -> dependency) for one task's blocking relations.
/// Blocks, WaitsFor, and ConditionalBlocks all constitute blocking edges.
pub fn dependency_edges(task: Task) -> List(#(String, String)) {
  task.relationships
  |> list.filter(fn(r) { is_blocking_relation(r.relation) })
  |> list.map(fn(r) { #(task.id, r.target_id) })
}

/// Returns True when a relationship type requires its target to be satisfied.
pub fn is_blocking_relation(rel: types.RelationType) -> Bool {
  case rel {
    Blocks -> True
    WaitsFor -> True
    ConditionalBlocks -> True
    _ -> False
  }
}

/// All dependency edges across a set of tasks.
pub fn all_edges(tasks: List(Task)) -> List(#(String, String)) {
  list.flat_map(tasks, dependency_edges)
}

/// Edges that participate in a dependency cycle (`cycles`). An edge
/// `(a -> b)` means `a depends on b`; it is cyclic when `b` can reach `a`.
/// Self-loops count. Every blocking relation participates because `all_edges`
/// filters through `is_blocking_relation`.
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

/// Would adding a child with `parent_id` to `tasks` create a parent hierarchy
/// cycle? A cycle occurs if the proposed parent is already a descendant of the
/// proposed child (walking parent_id chains upward).
pub fn would_cycle_parent_chain(
  tasks: List(Task),
  child_id: String,
  proposed_parent_id: String,
) -> Bool {
  // Self-loop
  case child_id == proposed_parent_id {
    True -> True
    // A parent cannot already have child_id in its own ancestor chain upward.
    False -> parent_chain_reaches(tasks, proposed_parent_id, child_id)
  }
}

/// Walk parent_id chains from `start_id` upward. Return True if `target_id`
/// appears as any ancestor's parent_id.
fn parent_chain_reaches(
  tasks: List(Task),
  start_id: String,
  target_id: String,
) -> Bool {
  parent_chain_walk(tasks, start_id, target_id, set.new())
}

fn parent_chain_walk(
  tasks: List(Task),
  current_id: String,
  target_id: String,
  visited: Set(String),
) -> Bool {
  case set.contains(visited, current_id) {
    True -> False
    False -> {
      let visited = set.insert(visited, current_id)
      case list.find(tasks, fn(t) { t.id == current_id }) {
        Error(Nil) -> False
        Ok(task) ->
          case task.parent_id {
            option.Some(pid) ->
              case pid == target_id {
                True -> True
                False -> parent_chain_walk(tasks, pid, target_id, visited)
              }
            option.None -> False
          }
      }
    }
  }
}

/// A task is ready iff it is active (not Completed/Closed) AND every blocking
/// relationship target is present in the supplied satisfied-id set. Context-free
/// callers normally use `ready_tasks`; `is_ready` remains the low-level predicate.
/// ParentChild and informational relations do not block readiness.
pub fn is_ready(task: Task, done: Set(String)) -> Bool {
  is_ready_at(task, done, 0)
}

pub fn is_ready_at(task: Task, done: Set(String), now: Int) -> Bool {
  is_active(task.status)
  && gate_is_open(task, now)
  && list.all(task.relationships, fn(r) {
    case is_blocking_relation(r.relation) {
      True -> set.contains(done, r.target_id)
      False -> True
    }
  })
}

/// Gates do not derive readiness from task status. A manual gate opens only
/// after explicit satisfaction; a timer gate opens once its due timestamp is
/// reached. This pure policy is credential-free and leaves PR/CI/remote gate
/// adapters as future producers of the same `gate_satisfied` fact.
pub fn gate_is_open(task: Task, now: Int) -> Bool {
  case task.kind {
    Gate ->
      case task.gate_satisfied {
        True -> True
        False ->
          case task.gate_due {
            option.Some(due) -> due <= now
            option.None -> False
          }
      }
    _ -> True
  }
}

/// All currently-ready executable work at `now`. An open gate is a satisfied
/// dependency fact, not a work item, so gates never appear in this list.
pub fn ready_tasks(tasks: List(Task)) -> List(Task) {
  ready_tasks_at(tasks, 0)
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

// BUG-03 fix: Closed work never satisfies a dependency. A Completed task does;
// a Gate satisfies it when its local manual/timer/signed fact is open at `now`.
fn satisfied_ids_at(tasks: List(Task), now: Int) -> Set(String) {
  tasks
  |> list.filter(fn(task) { blocker_is_satisfied(task, now) })
  |> list.map(fn(task) { task.id })
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

/// Ready executable work at `now`, excluding deferred tasks, gate facts, and wisps.
pub fn ready_tasks_at(tasks: List(Task), now: Int) -> List(Task) {
  let satisfied = satisfied_ids_at(tasks, now)
  tasks
  |> list.filter(fn(task) {
    task.kind != Gate
    && task.kind != types.Wisp
    && !is_deferred(task, now)
    && is_ready_at(task, satisfied, now)
  })
  |> list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
}

pub fn is_deferred(task: Task, now: Int) -> Bool {
  case task.defer_until {
    option.Some(until) -> until > now
    option.None -> False
  }
}

/// Context-aware readiness treats an open gate as a satisfied blocker. This is
/// how timer/manual/signed gate resolution deterministically wakes waiters
/// without rewriting each waiter's relationship or status.
pub fn task_is_ready(task: Task, tasks: List(Task), now: Int) -> Bool {
  task.kind != Gate
  && task.kind != types.Wisp
  && is_active(task.status)
  && !is_deferred(task, now)
  && list.all(task.relationships, fn(relation) {
    case is_blocking_relation(relation.relation) {
      False -> True
      True ->
        list.any(tasks, fn(target) {
          target.id == relation.target_id && blocker_is_satisfied(target, now)
        })
    }
  })
}

fn blocker_is_satisfied(task: Task, now: Int) -> Bool {
  case task.kind {
    Gate -> gate_is_open(task, now)
    types.Wisp -> False
    _ -> task.status == Completed
  }
}

/// Explain readiness from the same predicates used by `ready_tasks_at`.
/// The output is stable data: clients never need to reconstruct policy.
pub fn readiness_explanation(
  task: Task,
  tasks: List(Task),
  now: Int,
) -> json.Json {
  let active = is_active(task.status)
  let executable = task.kind != Gate && task.kind != types.Wisp
  let deferred = is_deferred(task, now)
  let gate_open = gate_is_open(task, now)
  let blockers =
    task.relationships
    |> list.filter(fn(relation) { is_blocking_relation(relation.relation) })
    |> list.sort(by: fn(a, b) { string.compare(a.target_id, b.target_id) })
    |> list.map(fn(relation) {
      let target =
        list.find(tasks, fn(candidate) { candidate.id == relation.target_id })
      let #(present, satisfied, status) = case target {
        Ok(found) -> #(
          True,
          blocker_is_satisfied(found, now),
          status_name(found.status),
        )
        Error(Nil) -> #(False, False, "missing")
      }
      json.object([
        #("target_id", json.string(relation.target_id)),
        #("relation", json.string(relation_name(relation.relation))),
        #("present", json.bool(present)),
        #("status", json.string(status)),
        #("satisfied", json.bool(satisfied)),
      ])
    })
  let blockers_clear =
    list.all(task.relationships, fn(relation) {
      case is_blocking_relation(relation.relation) {
        False -> True
        True ->
          list.any(tasks, fn(target) {
            target.id == relation.target_id && blocker_is_satisfied(target, now)
          })
      }
    })
  let ready = executable && active && !deferred && blockers_clear
  json.object([
    #("task_id", json.string(task.id)),
    #("ready", json.bool(ready)),
    #("active", json.bool(active)),
    #("executable", json.bool(executable)),
    #("status", json.string(status_name(task.status))),
    #("deferred", json.bool(deferred)),
    #("defer_until", json.nullable(task.defer_until, of: json.int)),
    #("gate_open", json.bool(gate_open)),
    #("gate_satisfied", json.bool(task.gate_satisfied)),
    #("gate_due", json.nullable(task.gate_due, of: json.int)),
    #("claimable", json.bool(ready && task.assignee == option.None)),
    #("blockers", json.array(blockers, of: fn(value) { value })),
  ])
}

fn status_name(status: TaskStatus) -> String {
  case status {
    Open -> "open"
    InProgress -> "in_progress"
    Blocked -> "blocked"
    Completed -> "completed"
    Closed -> "closed"
  }
}

fn relation_name(relation: types.RelationType) -> String {
  case relation {
    Blocks -> "blocks"
    WaitsFor -> "waits_for"
    ConditionalBlocks -> "conditional_blocks"
    _ -> "informational"
  }
}
