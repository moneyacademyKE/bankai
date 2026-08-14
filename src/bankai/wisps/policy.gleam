import bankai/builder
import bankai/serde
import bankai/types.{type Task, DefaultTask, Task, Wisp}
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleamunison/identity

pub type State {
  Active
  Expired
}

pub fn state(expiry: Option(Int), now: Int) -> State {
  case expiry {
    option.Some(at) if at <= now -> Expired
    _ -> Active
  }
}

pub fn is_expired(expiry: Option(Int), now: Int) -> Bool {
  state(expiry, now) == Expired
}

pub fn promote(task: Task, now: Int) -> Result(Task, String) {
  case task.kind {
    Wisp ->
      Ok(
        builder.update(task, fn(current) {
          Task(..current, kind: DefaultTask, updated_at: now)
        }),
      )
    _ -> Error("task is not a wisp: " <> task.id)
  }
}

pub fn digest(task: Task, expiry: Option(Int), state: State) -> json.Json {
  let source =
    json.object([
      #("schema", json.int(1)),
      #("task", serde.task_to_json(task)),
      #("expires_at", json.nullable(expiry, of: json.int)),
      #("state", json.string(state_name(state))),
    ])
    |> json.to_string
  json.object([
    #("wisp_id", json.string(task.id)),
    #("content_hash", json.string(hash(source))),
    #("state", json.string(state_name(state))),
    #("source_history_preserved", json.bool(True)),
  ])
}

pub fn filter_state(
  tasks: List(#(Task, Option(Int))),
  wanted: String,
  now: Int,
) -> Result(List(#(Task, Option(Int))), String) {
  case wanted {
    "all" -> Ok(tasks)
    "active" ->
      Ok(list.filter(tasks, fn(pair) { state(pair.1, now) == Active }))
    "expired" ->
      Ok(list.filter(tasks, fn(pair) { state(pair.1, now) == Expired }))
    _ -> Error("wisp state must be all, active, or expired")
  }
}

fn state_name(value: State) -> String {
  case value {
    Active -> "active"
    Expired -> "expired"
  }
}

fn hash(value: String) -> String {
  value
  |> bit_array.from_string
  |> identity.hash_bytes
  |> identity.hash_to_debug_string
}
