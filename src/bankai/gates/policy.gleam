import bankai/graph
import bankai/serde
import bankai/types.{type Task, type TaskStatus, Gate, Task}
import gleam/json

import gleam/list
import gleam/option
import gleam/string

pub type State {
  OpenByResolution
  OpenByTimer
  OpenByFact
  PendingManual
  PendingTimer
  PendingFact
}

pub fn evaluate(
  gate: Task,
  tasks: List(Task),
  stored_fact_satisfied: Bool,
  now: Int,
) -> json.Json {
  let state = state(gate, stored_fact_satisfied, now)
  let waiter_tasks = waiters(gate.id, tasks)
  let preview_gate = Task(..gate, gate_satisfied: True)
  let preview_tasks =
    tasks
    |> list.map(fn(task) {
      case task.id == gate.id {
        True -> preview_gate
        False -> task
      }
    })
  json.object([
    #("gate", serde.task_to_json(gate)),
    #("open", json.bool(is_open(state))),
    #("state", json.string(state_name(state))),
    #("reasons", json.array(reasons(state), of: json.string)),
    #(
      "waiters",
      json.array(waiter_tasks, of: fn(task) {
        json.object([
          #("task_id", json.string(task.id)),
          #("title", json.string(task.title)),
          #("status", json.string(status_name(task.status))),
          #(
            "ready_if_resolved",
            json.bool(graph.task_is_ready(task, preview_tasks, now)),
          ),
        ])
      }),
    ),
  ])
}

pub fn state(gate: Task, stored_fact_satisfied: Bool, now: Int) -> State {
  case gate.kind {
    Gate ->
      case gate.gate_satisfied, gate.gate_due, stored_fact_satisfied {
        True, _, _ -> OpenByResolution
        False, option.Some(due), _ if due <= now -> OpenByTimer
        False, _, True -> OpenByFact
        False, option.Some(_), _ -> PendingTimer
        False, option.None, False -> PendingManual
      }
    _ -> PendingFact
  }
}

pub fn waiters(gate_id: String, tasks: List(Task)) -> List(Task) {
  tasks
  |> list.filter(fn(task) {
    task.relationships
    |> list.any(fn(relation) {
      relation.target_id == gate_id
      && graph.is_blocking_relation(relation.relation)
    })
  })
  |> list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
}

pub fn is_open(state: State) -> Bool {
  case state {
    OpenByResolution | OpenByTimer | OpenByFact -> True
    PendingManual | PendingTimer | PendingFact -> False
  }
}

pub fn reasons(state: State) -> List(String) {
  case state {
    OpenByResolution -> ["resolved"]
    OpenByTimer -> ["timer_due"]
    OpenByFact -> ["signed_fact_satisfied"]
    PendingManual -> ["manual_resolution_required"]
    PendingTimer -> ["timer_not_due"]
    PendingFact -> ["valid_signed_fact_required"]
  }
}

fn state_name(state: State) -> String {
  case state {
    OpenByResolution -> "resolved"
    OpenByTimer -> "timer_open"
    OpenByFact -> "fact_open"
    PendingManual -> "manual_pending"
    PendingTimer -> "timer_pending"
    PendingFact -> "fact_pending"
  }
}

fn status_name(status: TaskStatus) -> String {
  case status {
    types.Open -> "open"
    types.InProgress -> "in_progress"
    types.Blocked -> "blocked"
    types.Completed -> "completed"
    types.Closed -> "closed"
  }
}
