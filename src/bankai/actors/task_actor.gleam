//// The TaskActor: one supervised gleam_otp/actor process per active task.
////
//// It is the single authority for its task's state. Sequential message handling
//// gives linearizability without locks. Every mutation rehashes (content_hash
//// advances). Cycle detection on AddRelation uses the pure graph module, gated
//// by validation.relation_ok over the coordinator-supplied graph context.

import gleam/erlang/process
import gleam/otp/actor
import bankai/actors/apply
import bankai/actors/messages.{
  type TaskMessage, AddRelation, GetState, UpdateStatus,
}
import bankai/actors/validation
import bankai/time
import bankai/types.{type Task, type TaskStatus}

/// Spawn a TaskActor for `task`. Returns the actor handle (its Subject).
pub fn start(
  task: Task,
) -> Result(actor.Started(process.Subject(TaskMessage)), actor.StartError) {
  actor.new(task)
  |> actor.on_message(handle)
  |> actor.start()
}

/// Synchronously apply a status change; returns the updated, rehashed Task.
pub fn update_status(
  subject: process.Subject(TaskMessage),
  status: TaskStatus,
  timeout_ms: Int,
) -> Result(Task, String) {
  actor.call(subject, waiting: timeout_ms, sending: fn(reply_to) {
    UpdateStatus(status, reply_to)
  })
}

/// Synchronously add a Blocks dependency; cycle-gated.
pub fn add_relation(
  subject: process.Subject(TaskMessage),
  target_id: String,
  all_edges: List(#(String, String)),
  timeout_ms: Int,
) -> Result(Task, String) {
  actor.call(subject, waiting: timeout_ms, sending: fn(reply_to) {
    AddRelation(target_id, all_edges, reply_to)
  })
}

/// Synchronously read the current Task.
pub fn get_state(
  subject: process.Subject(TaskMessage),
  timeout_ms: Int,
) -> Task {
  actor.call(subject, waiting: timeout_ms, sending: fn(reply_to) {
    GetState(reply_to)
  })
}

// --- handler ---

fn handle(task: Task, msg: TaskMessage) -> actor.Next(Task, TaskMessage) {
  case msg {
    UpdateStatus(status, reply_to) -> {
      let updated = apply.status(task, status, time.now())
      process.send(reply_to, Ok(updated))
      actor.continue(updated)
    }

    AddRelation(target_id, all_edges, reply_to) ->
      case validation.relation_ok(task.id, target_id, all_edges) {
        Ok(Nil) -> {
          let updated = apply.relation(task, target_id, time.now())
          process.send(reply_to, Ok(updated))
          actor.continue(updated)
        }
        Error(reason) -> {
          process.send(reply_to, Error(reason))
          actor.continue(task)
        }
      }

    GetState(reply_to) -> {
      process.send(reply_to, task)
      actor.continue(task)
    }
  }
}
