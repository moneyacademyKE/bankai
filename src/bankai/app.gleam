//// The bankai application: a supervision tree (OneForOne) whose durable root
//// is the Store actor. Task actors are spawned on demand from the store, so a
//// killed task actor is restored from durable state on the next spawn.
////
//// Full factory_supervisor auto-restart of task actors is a Phase 8 refinement;
//// this MVP proves the supervision tree boots and that task state survives
//// actor crashes via the store.

import gleam/erlang/process
import gleam/otp/actor
import gleam/otp/static_supervisor
import gleam/otp/supervision
import bankai/actors/messages.{type TaskMessage}
import bankai/actors/task_actor
import bankai/storage/store
import bankai/store_actor
import bankai/types.{type Task}

pub opaque type App {
  App(
    store_name: process.Name(store_actor.StoreMsg),
    supervisor: actor.Started(static_supervisor.Supervisor),
  )
}

/// Boot the supervision tree with an initial set of tasks.
pub fn start(
  initial: List(Task),
) -> Result(App, actor.StartError) {
  let store_name = process.new_name(prefix: "bankai_store")
  let builder =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(supervision.worker(fn() {
      store_actor.start_named(store_name, store.from_list(initial))
    }))

  case static_supervisor.start(builder) {
    Ok(supervisor) -> Ok(App(store_name:, supervisor:))
    Error(e) -> Error(e)
  }
}

/// Address the supervised Store actor by its registered name.
pub fn store_subject(app: App) -> process.Subject(store_actor.StoreMsg) {
  process.named_subject(app.store_name)
}

/// Spawn (or re-spawn) a TaskActor for a task, reading current state from the
/// durable store. This is the recovery path: a killed actor is restored here.
pub fn spawn_task_actor(
  app: App,
  id: String,
  timeout_ms: Int,
) -> Result(actor.Started(process.Subject(TaskMessage)), String) {
  case store_actor.get_by_id(store_subject(app), id, timeout_ms) {
    Ok(task) ->
      case task_actor.start(task) {
        Ok(started) -> Ok(started)
        Error(_) -> Error("failed to start task actor")
      }
    Error(Nil) -> Error("no such task: " <> id)
  }
}
