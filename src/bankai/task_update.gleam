//// One owner for composed task-field updates.
////
//// Both the CLI's local file path and the daemon's Mnesia path parse the
//// same `parser.UpdateArgs` into `Fields`, then call `apply` to decide
//// whether anything changed and to produce the next task version. Keeping
//// that decision here means a new updatable field is added once, not once
//// per transport.

import bankai/builder
import bankai/cli/parser
import bankai/lease
import bankai/serde
import bankai/time
import bankai/types.{
  type Task, type TaskStatus, Closed, Completed, InProgress, Task,
}
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/result

/// The subset of `parser.UpdateArgs` that the composed update applies.
/// `force` stays out: it only modifies the claim guard, not the fields.
pub type Fields {
  Fields(
    status: Option(TaskStatus),
    claim: Option(String),
    ttl: Option(String),
    labels: List(String),
    priority: Option(Int),
    title: Option(String),
    description: Option(String),
    defer_until: Option(Int),
  )
}

/// Parse the raw update grammar into the typed fields the store applies.
/// Validation order matches the old CLI path: status, priority, defer.
pub fn fields_from_args(args: parser.UpdateArgs) -> Result(Fields, String) {
  let status = case args.status {
    option.None -> Ok(option.None)
    option.Some(s) ->
      case serde.status_from_string(s) {
        Ok(parsed) -> Ok(option.Some(parsed))
        Error(Nil) -> Error("invalid status: " <> s)
      }
  }
  use status <- result.try(status)
  let priority = case args.priority {
    option.None -> Ok(option.None)
    option.Some(p) ->
      case int.parse(p) {
        Ok(parsed) ->
          case parser.validate_priority(parsed) {
            Ok(valid) -> Ok(option.Some(valid))
            Error(message) -> Error(message)
          }
        Error(_) -> Error("invalid priority: " <> p)
      }
  }
  use priority <- result.try(priority)
  let defer_until = case args.defer_until {
    option.None -> Ok(option.None)
    option.Some(d) ->
      case int.parse(d) {
        Ok(parsed) -> Ok(option.Some(parsed))
        Error(_) -> Error("defer timestamp must be an integer")
      }
  }
  use defer_until <- result.try(defer_until)
  Ok(Fields(
    status: status,
    claim: args.claim,
    ttl: args.ttl,
    labels: args.labels,
    priority: priority,
    title: args.title,
    description: args.description,
    defer_until: defer_until,
  ))
}

/// Apply `fields` to `previous`. Returns `#(changed, task)`: `changed` is
/// False for an idempotent no-op (the caller must not write a new version),
/// True when the returned task is the next immutable version.
pub fn apply(previous: Task, fields: Fields) -> #(Bool, Task) {
  let effective_status = case fields.status, fields.claim {
    option.Some(s), _ -> option.Some(s)
    // Claim implies InProgress when no explicit status was given:
    // one claim semantic on every path (bk-9f48 groundwork).
    option.None, option.Some(_) -> option.Some(InProgress)
    option.None, option.None -> option.None
  }
  let added_labels =
    list.filter(fields.labels, fn(l) { !list.contains(previous.labels, l) })
  let changed =
    added_labels != []
    || case fields.claim {
      // A re-claim always renews the lease, so it always counts as a change.
      option.None -> False
      option.Some(_) -> True
    }
    || case fields.priority {
      option.None -> False
      option.Some(p) -> previous.priority != p
    }
    || case fields.title {
      option.None -> False
      option.Some(t) -> previous.title != t
    }
    || case fields.description {
      option.None -> False
      option.Some(d) -> previous.description != d
    }
    || case effective_status {
      option.None -> False
      option.Some(s) -> previous.status != s
    }
    || case fields.defer_until {
      option.None -> False
      option.Some(d) -> previous.defer_until != option.Some(d)
    }
  case changed {
    False -> #(False, previous)
    True -> {
      let updated =
        builder.update(previous, fn(task) {
          let task = case added_labels {
            [] -> task
            new -> Task(..task, labels: list.append(new, task.labels))
          }
          let task = case fields.claim {
            option.None -> task
            option.Some(assignee) ->
              // A claim stamps a fresh lease (bk-ccbf); re-claim renews.
              Task(
                ..task,
                assignee: option.Some(assignee),
                claim_lease_expires_at: lease.fresh(
                  time.now(),
                  lease.ttl_from(fields.ttl),
                ),
              )
          }
          let task = case fields.priority {
            option.None -> task
            option.Some(p) -> Task(..task, priority: p)
          }
          let task = case fields.title {
            option.None -> task
            option.Some(v) -> Task(..task, title: v)
          }
          let task = case fields.description {
            option.None -> task
            option.Some(v) -> Task(..task, description: v)
          }
          let task = case effective_status {
            option.None -> task
            option.Some(s) -> Task(..task, status: s)
          }
          let task = case fields.defer_until {
            option.None -> task
            option.Some(d) -> Task(..task, defer_until: option.Some(d))
          }
          // Terminal statuses retire the lease with the claim (bk-ccbf).
          let task = case effective_status {
            option.Some(Closed) | option.Some(Completed) ->
              Task(..task, claim_lease_expires_at: option.None)
            _ -> task
          }
          Task(..task, updated_at: time.now())
        })
      #(True, updated)
    }
  }
}
