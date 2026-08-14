import bankai/builder
import bankai/serde
import bankai/types.{type Task, Closed, InProgress, Open, Task}
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string

pub type Mutation {
  Release(id: String)
  Reopen(id: String)
  Undefer(id: String)
  RemoveLabel(id: String, label: String)
  SetStatus(id: String, status: types.TaskStatus)
  SetPriority(id: String, priority: Int)
}

/// Compact wire format: `release:<id>`, `reopen:<id>`, `undefer:<id>`,
/// `label_remove:<id>:<label>`, `status:<id>:<status>`, `priority:<id>:<int>`.
pub fn parse(encoded: String) -> Result(Mutation, String) {
  case string.split(encoded, ":") {
    ["release", id] -> Ok(Release(id))
    ["reopen", id] -> Ok(Reopen(id))
    ["undefer", id] -> Ok(Undefer(id))
    ["label_remove", id, label] -> Ok(RemoveLabel(id, label))
    ["status", id, status] ->
      serde.status_from_string(status)
      |> result.map_error(fn(_) { "invalid batch status: " <> status })
      |> result.map(fn(value) { SetStatus(id, value) })
    ["priority", id, value] ->
      int.parse(value)
      |> result.map_error(fn(_) { "invalid batch priority: " <> value })
      |> result.map(fn(priority) { SetPriority(id, priority) })
    _ -> Error("invalid batch mutation: " <> encoded)
  }
}

pub fn id(mutation: Mutation) -> String {
  case mutation {
    Release(id)
    | Reopen(id)
    | Undefer(id)
    | RemoveLabel(id, _)
    | SetStatus(id, _)
    | SetPriority(id, _) -> id
  }
}

pub fn apply(task: Task, mutation: Mutation, now: Int) -> Result(Task, String) {
  case mutation {
    Release(_) -> release(task, now)
    Reopen(_) -> reopen(task, now)
    Undefer(_) -> undefer(task, now)
    RemoveLabel(_, label) -> remove_label(task, label, now)
    SetStatus(_, status) -> set_status(task, status, now)
    SetPriority(_, priority) -> set_priority(task, priority, now)
  }
}

fn release(task: Task, now: Int) -> Result(Task, String) {
  case task.status {
    InProgress ->
      Ok(
        builder.update(task, fn(current) {
          Task(..current, status: Open, assignee: option.None, updated_at: now)
        }),
      )
    Open ->
      case task.assignee {
        option.None -> Ok(task)
        option.Some(_) ->
          Ok(
            builder.update(task, fn(current) {
              Task(..current, assignee: option.None, updated_at: now)
            }),
          )
      }
    _ -> Error("release requires an in_progress task: " <> task.id)
  }
}

fn reopen(task: Task, now: Int) -> Result(Task, String) {
  case task.status {
    types.Completed | Closed ->
      Ok(
        builder.update(task, fn(current) {
          Task(
            ..current,
            status: Open,
            closure_reason: option.None,
            updated_at: now,
          )
        }),
      )
    Open -> Ok(task)
    _ -> Error("reopen requires a completed or closed task: " <> task.id)
  }
}

fn undefer(task: Task, now: Int) -> Result(Task, String) {
  case task.defer_until {
    option.None -> Ok(task)
    option.Some(_) ->
      Ok(
        builder.update(task, fn(current) {
          Task(..current, defer_until: option.None, updated_at: now)
        }),
      )
  }
}

fn remove_label(task: Task, label: String, now: Int) -> Result(Task, String) {
  case list.contains(task.labels, label) {
    False -> Ok(task)
    True ->
      Ok(
        builder.update(task, fn(current) {
          Task(
            ..current,
            labels: list.filter(current.labels, fn(value) { value != label }),
            updated_at: now,
          )
        }),
      )
  }
}

fn set_status(
  task: Task,
  status: types.TaskStatus,
  now: Int,
) -> Result(Task, String) {
  case task.status == status {
    True -> Ok(task)
    False ->
      Ok(
        builder.update(task, fn(current) {
          Task(..current, status: status, updated_at: now)
        }),
      )
  }
}

fn set_priority(task: Task, priority: Int, now: Int) -> Result(Task, String) {
  case task.priority == priority {
    True -> Ok(task)
    False ->
      Ok(
        builder.update(task, fn(current) {
          Task(..current, priority: priority, updated_at: now)
        }),
      )
  }
}
