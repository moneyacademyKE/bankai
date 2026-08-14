//// Complete local wisp lifecycle service. Wisps remain task-shaped but their
//// TTL metadata and disposal evidence live in separate lifecycle tables.

import bankai/gate_wisp/store as lifecycle_store
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/time
import bankai/types.{type Task, Wisp}
import bankai/wisps/policy
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleamunison/identity

pub fn list(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  let wanted = option_value(args, "--state", "all")
  let now = time.now()
  use wisps <- result.try(wisps_with_expiry(workspace))
  use filtered <- result.try(policy.filter_state(wisps, wanted, now))
  Ok(
    json.array(filtered, of: fn(pair) {
      let #(task, expiry) = pair
      json.object([
        #("task", serde.task_to_json(task)),
        #("expires_at", json.nullable(expiry, of: json.int)),
        #(
          "state",
          json.string(case policy.state(expiry, now) {
            policy.Active -> "active"
            policy.Expired -> "expired"
          }),
        ),
      ])
    }),
  )
}

pub fn create(
  workspace: String,
  task: Task,
  args: List(String),
) -> Result(Task, String) {
  let now = time.now()
  use expiry <- result.try(parse_expiry(args, now))
  lifecycle_store.create_wisp(
    workspace,
    task.id,
    hash(task),
    serde.task_to_json_string(task),
    expiry,
  )
  |> result.try(serde.task_from_json_string)
}

pub fn promote(
  workspace: String,
  id: String,
  args: List(String),
) -> Result(json.Json, String) {
  use previous <- result.try(get_wisp(workspace, id))
  let now = time.now()
  use updated <- result.try(policy.promote(previous, now))
  let actor = option_value(args, "--actor", "local")
  let reason = option_value(args, "--reason", "promoted local wisp")
  use sequence <- result.try(lifecycle_store.promote_wisp(
    workspace,
    id,
    hash(previous),
    hash(updated),
    serde.task_to_json_string(updated),
    actor,
    reason,
    now,
  ))
  Ok(
    json.object([
      #("task", serde.task_to_json(updated)),
      #("archive_sequence", json.int(sequence)),
      #("source_history_preserved", json.bool(True)),
    ]),
  )
}

pub fn digest(workspace: String, id: String) -> Result(json.Json, String) {
  use task <- result.try(get_wisp(workspace, id))
  use expiry <- result.try(lifecycle_store.wisp_expiry(workspace, id))
  Ok(policy.digest(task, expiry, policy.state(expiry, time.now())))
}

pub fn burn(
  workspace: String,
  id: String,
  args: List(String),
) -> Result(json.Json, String) {
  use task <- result.try(get_wisp(workspace, id))
  let actor = option_value(args, "--actor", "local")
  let reason = option_value(args, "--reason", "explicit wisp burn")
  use count <- result.try(lifecycle_store.burn_wisps(
    workspace,
    [#(task.id, hash(task), -1)],
    "burn",
    actor,
    reason,
    time.now(),
  ))
  Ok(burn_result(count, [task.id], "burn"))
}

pub fn gc(workspace: String, args: List(String)) -> Result(json.Json, String) {
  let now = time.now()
  let dry_run = has_flag(args, "--dry-run")
  let actor = option_value(args, "--actor", "gc")
  let reason = option_value(args, "--reason", "expired wisp gc")
  use wisps <- result.try(wisps_with_expiry(workspace))
  let expired =
    wisps
    |> list.filter(fn(pair) { policy.is_expired(pair.1, now) })
    |> list.sort(by: fn(a, b) { string.compare(a.0.id, b.0.id) })
  let ids = list.map(expired, fn(pair) { pair.0.id })
  case dry_run {
    True ->
      Ok(
        json.object([
          #("dry_run", json.bool(True)),
          #("count", json.int(list.length(ids))),
          #("wisp_ids", json.array(ids, of: json.string)),
          #("policy", json.string("expired_at_or_before_now")),
        ]),
      )
    False -> {
      let rows =
        list.filter_map(expired, fn(pair) {
          case pair.1 {
            option.Some(expiry) -> Ok(#(pair.0.id, hash(pair.0), expiry))
            option.None -> Error(Nil)
          }
        })
      use count <- result.try(lifecycle_store.burn_wisps(
        workspace,
        rows,
        "gc",
        actor,
        reason,
        now,
      ))
      Ok(burn_result(count, ids, "gc"))
    }
  }
}

pub fn archives(workspace: String, id: String) -> Result(json.Json, String) {
  lifecycle_store.wisp_archives(workspace, id)
  |> result.map(fn(rows) {
    json.array(rows, of: fn(row) {
      json.object([
        #("sequence", json.int(row.sequence)),
        #("wisp_id", json.string(row.wisp_id)),
        #("action", json.string(row.action)),
        #("actor", json.string(row.actor)),
        #("reason", json.string(row.reason)),
        #("task_hash", json.string(row.task_hash)),
        #("task", json.string(row.task_json)),
        #("at", json.int(row.at)),
      ])
    })
  })
}

fn wisps_with_expiry(
  workspace: String,
) -> Result(List(#(Task, Option(Int))), String) {
  use index <- result.try(mnesia_store.current_store(workspace))
  index
  |> store.current_tasks()
  |> list.filter(fn(task) { task.kind == Wisp })
  |> list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
  |> list.try_map(fn(task) {
    lifecycle_store.wisp_expiry(workspace, task.id)
    |> result.map(fn(expiry) { #(task, expiry) })
  })
}

fn get_wisp(workspace: String, id: String) -> Result(Task, String) {
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(task) {
    case task.kind {
      Wisp -> Ok(task)
      _ -> Error("task is not a wisp: " <> id)
    }
  })
}

fn parse_expiry(args: List(String), now: Int) -> Result(Option(Int), String) {
  case args {
    ["--expires-at", value, ..] ->
      int.parse(value)
      |> result.map(option.Some)
      |> result.map_error(fn(_) { "wisp --expires-at must be an integer" })
    ["--ttl", value, ..] ->
      int.parse(value)
      |> result.map_error(fn(_) { "wisp --ttl must be an integer" })
      |> result.try(fn(ttl) {
        case ttl > 0 {
          True -> Ok(option.Some(now + ttl * 1_000_000_000))
          False -> Error("wisp --ttl must be positive seconds")
        }
      })
    [_, ..rest] -> parse_expiry(rest, now)
    [] -> Ok(option.None)
  }
}

fn burn_result(count: Int, ids: List(String), action: String) -> json.Json {
  json.object([
    #("action", json.string(action)),
    #("archived_before_removal", json.bool(True)),
    #("count", json.int(count)),
    #("wisp_ids", json.array(ids, of: json.string)),
  ])
}

fn option_value(args: List(String), name: String, default: String) -> String {
  case args {
    [flag, value, ..] if flag == name -> value
    [_, ..rest] -> option_value(rest, name, default)
    [] -> default
  }
}

fn has_flag(args: List(String), wanted: String) -> Bool {
  list.any(args, fn(value) { value == wanted })
}

fn hash(task: Task) -> String {
  identity.hash_to_debug_string(task.content_hash)
}
