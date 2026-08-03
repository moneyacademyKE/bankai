//// Messages handled by a TaskActor process. Synchronous requests carry a
//// reply Subject so callers can use actor.call for linearizable reads/writes.

import bankai/types.{type Task, type TaskStatus}
import gleam/erlang/process.{type Subject}

pub type TaskMessage {
  /// Apply a status change; replies with the updated Task (rehashed).
  UpdateStatus(status: TaskStatus, reply_to: Subject(Result(Task, String)))

  /// Add a Blocks dependency edge (this task is blocked by target_id).
  /// `all_edges` is the coordinator's current full graph context, used for the
  /// cycle gate. Replies Ok(updated) or Error(reason).
  AddRelation(
    target_id: String,
    all_edges: List(#(String, String)),
    reply_to: Subject(Result(Task, String)),
  )

  /// Read the actor's current Task.
  GetState(reply_to: Subject(Task))
}
