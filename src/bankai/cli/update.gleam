//// The update command family: one grammar, one composed rewrite.

import bankai/builder
import bankai/cli/parser
import bankai/lease
import bankai/serde
import bankai/storage/store
import bankai/sync/jsonl
import bankai/task_update
import bankai/time
import bankai/types.{type Task, InProgress, Open, Task}
import gleam/json
import gleam/option
import gleam/result

pub fn update_dispatch(
  tasks_path: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  // Heartbeat is exclusive: it refreshes a live claim's lease and combines
  // with nothing (a fresh claim already stamps a lease).
  case args.heartbeat {
    True ->
      case parser.simple_fields_requested(args) {
        False -> heartbeat_cmd(tasks_path, args.id, args.ttl)
        True -> Error("--heartbeat does not combine with other update fields")
      }
    False -> update_dispatch_rest(tasks_path, args)
  }
}

pub fn update_dispatch_rest(
  tasks_path: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  // Daemon-only lifecycle verbs fail loudly here rather than being ignored.
  case
    args.release
    || args.reopen
    || args.undefer
    || args.satisfy_gate
    || args.close != option.None
    || args.fence != option.None
    || args.remove_labels != []
  {
    True ->
      Error(
        "that update verb requires the bankai daemon (start it with `bankai serve`)",
      )
    False -> apply_update(tasks_path, args)
  }
}

pub fn apply_update(
  tasks_path: String,
  args: parser.UpdateArgs,
) -> Result(json.Json, String) {
  use fields <- result.try(task_update.fields_from_args(args))
  // --force is only meaningful alongside --claim.
  use Nil <- result.try(case args.force, args.claim {
    True, option.None -> Error("--force only applies with --claim")
    _, _ -> Ok(Nil)
  })
  use index <- result.try(jsonl.load_store(from: tasks_path))
  case store.find_by_id(index, args.id) {
    Error(Nil) -> Error("no such task: " <> args.id)
    Ok(task) -> {
      // Claim guards (bk-9f48): only Open/InProgress tasks are claimable,
      // and a task owned by someone else needs --force to reclaim. Loud
      // beats clever: a silent steal corrupts the ledger.
      let claim_error = case args.claim {
        option.None -> option.None
        option.Some(new_claimant) ->
          case task.status {
            Open | InProgress ->
              case task.assignee, args.force {
                option.Some(owner), False ->
                  case owner == new_claimant {
                    True -> option.None
                    False ->
                      // bk-2f2a: an expired lease no longer blocks; the
                      // claim is effectively abandoned by a dead agent.
                      case
                        lease.is_expired(
                          task.claim_lease_expires_at,
                          time.now(),
                        )
                      {
                        True -> option.None
                        False ->
                          option.Some(
                            "already claimed by "
                            <> owner
                            <> " (use --force to reclaim)",
                          )
                      }
                  }
                _, _ -> option.None
              }
            _ -> option.Some("task is not open: " <> args.id)
          }
      }
      case claim_error {
        option.Some(message) -> Error(message)
        option.None -> apply_guarded_update(tasks_path, index, task, fields)
      }
    }
  }
}

pub fn apply_guarded_update(
  tasks_path: String,
  index: store.Store,
  task: Task,
  fields: task_update.Fields,
) -> Result(json.Json, String) {
  let #(changed, updated) = task_update.apply(task, fields)
  case changed {
    False -> Ok(serde.task_to_json(task))
    True -> {
      let index = store.put(index, updated)
      use _ <- result.try(jsonl.flush_report(store.list(index), to: tasks_path))
      Ok(serde.task_to_json(updated))
    }
  }
}

pub fn heartbeat_cmd(
  tasks_path: String,
  id: String,
  ttl: option.Option(String),
) -> Result(json.Json, String) {
  use index <- result.try(jsonl.load_store(from: tasks_path))
  case store.find_by_id(index, id) {
    Error(Nil) -> Error("no such task: " <> id)
    Ok(task) ->
      case task.assignee {
        option.None -> Error("task is not claimed: " <> id)
        option.Some(_) -> {
          let updated =
            builder.update(task, fn(t) {
              Task(
                ..t,
                claim_lease_expires_at: lease.fresh(
                  time.now(),
                  lease.ttl_from(ttl),
                ),
                updated_at: time.now(),
              )
            })
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
/// Free tasks whose claim lease has expired (bk-ccbf): back to open,
/// assignee and lease cleared. Returns the reclaimed ids.
