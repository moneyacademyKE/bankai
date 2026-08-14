import bankai/graph
import bankai/serde
import bankai/types.{
  type Task, Bug, Chore, Decision, DefaultTask, Epic, Feature, Gate, Wisp,
}
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/order.{type Order}
import gleam/result
import gleam/string

pub type SortField {
  ById
  ByPriority
  ByCreated
  ByUpdated
}

pub type Direction {
  Ascending
  Descending
}

pub type DeferredFilter {
  AnyDeferred
  DeferredOnly
  NotDeferred
}

pub type Spec {
  Spec(
    statuses: List(types.TaskStatus),
    kinds: List(types.TaskKind),
    priority_min: Option(Int),
    priority_max: Option(Int),
    assignee: Option(String),
    labels_any: List(String),
    labels_all: List(String),
    deferred: DeferredFilter,
    created_after: Option(Int),
    created_before: Option(Int),
    updated_after: Option(Int),
    updated_before: Option(Int),
    sort: SortField,
    direction: Direction,
    offset: Int,
    limit: Option(Int),
  )
}

pub fn default() -> Spec {
  Spec(
    [],
    [],
    option.None,
    option.None,
    option.None,
    [],
    [],
    AnyDeferred,
    option.None,
    option.None,
    option.None,
    option.None,
    ById,
    Ascending,
    0,
    option.None,
  )
}

pub fn parse(args: List(String)) -> Result(Spec, String) {
  do_parse(args, default())
}

fn do_parse(args: List(String), spec: Spec) -> Result(Spec, String) {
  case args {
    [] -> Ok(spec)
    ["--status", value, ..rest] ->
      serde.status_from_string(value)
      |> result.map_error(fn(_) { "invalid status: " <> value })
      |> result.try(fn(status) {
        do_parse(rest, Spec(..spec, statuses: [status, ..spec.statuses]))
      })
    ["--kind", value, ..rest] ->
      kind_from_string(value)
      |> result.try(fn(kind) {
        do_parse(rest, Spec(..spec, kinds: [kind, ..spec.kinds]))
      })
    ["--priority-min", value, ..rest] ->
      parse_int(value, "priority-min")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, priority_min: option.Some(n)))
      })
    ["--priority-max", value, ..rest] ->
      parse_int(value, "priority-max")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, priority_max: option.Some(n)))
      })
    ["--assignee", value, ..rest] ->
      do_parse(rest, Spec(..spec, assignee: option.Some(value)))
    ["--label", value, ..rest] | ["--label-any", value, ..rest] ->
      do_parse(rest, Spec(..spec, labels_any: [value, ..spec.labels_any]))
    ["--label-all", value, ..rest] ->
      do_parse(rest, Spec(..spec, labels_all: [value, ..spec.labels_all]))
    ["--deferred", ..rest] ->
      do_parse(rest, Spec(..spec, deferred: DeferredOnly))
    ["--not-deferred", ..rest] ->
      do_parse(rest, Spec(..spec, deferred: NotDeferred))
    ["--created-after", value, ..rest] ->
      parse_int(value, "created-after")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, created_after: option.Some(n)))
      })
    ["--created-before", value, ..rest] ->
      parse_int(value, "created-before")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, created_before: option.Some(n)))
      })
    ["--updated-after", value, ..rest] ->
      parse_int(value, "updated-after")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, updated_after: option.Some(n)))
      })
    ["--updated-before", value, ..rest] ->
      parse_int(value, "updated-before")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, updated_before: option.Some(n)))
      })
    ["--sort", value, ..rest] ->
      sort_from_string(value)
      |> result.try(fn(sort) { do_parse(rest, Spec(..spec, sort: sort)) })
    ["--desc", ..rest] -> do_parse(rest, Spec(..spec, direction: Descending))
    ["--asc", ..rest] -> do_parse(rest, Spec(..spec, direction: Ascending))
    ["--offset", value, ..rest] ->
      parse_non_negative(value, "offset")
      |> result.try(fn(n) { do_parse(rest, Spec(..spec, offset: n)) })
    ["--limit", value, ..rest] ->
      parse_non_negative(value, "limit")
      |> result.try(fn(n) {
        do_parse(rest, Spec(..spec, limit: option.Some(n)))
      })
    ["--compact", ..rest] -> do_parse(rest, spec)
    ["--explain", ..rest] -> do_parse(rest, spec)
    [flag, ..] -> Error("unknown task-view option: " <> flag)
  }
}

pub fn apply(tasks: List(Task), spec: Spec, now: Int) -> List(Task) {
  tasks
  |> list.filter(fn(task) { matches(task, spec, now) })
  |> list.sort(by: comparator(spec.sort, spec.direction))
  |> list.drop(spec.offset)
  |> apply_limit(spec.limit)
}

pub fn envelope(
  tasks: List(Task),
  spec: Spec,
  now: Int,
  compact: Bool,
) -> json.Json {
  let filtered = apply(tasks, Spec(..spec, offset: 0, limit: option.None), now)
  let page = filtered |> list.drop(spec.offset) |> apply_limit(spec.limit)
  json.object([
    #("tasks", json.array(page, of: fn(task) { task_json(task, compact) })),
    #("total", json.int(list.length(filtered))),
    #("offset", json.int(spec.offset)),
    #("returned", json.int(list.length(page))),
  ])
}

pub fn count(tasks: List(Task), spec: Spec, now: Int) -> json.Json {
  let matched = apply(tasks, Spec(..spec, offset: 0, limit: option.None), now)
  json.object([#("count", json.int(list.length(matched)))])
}

pub fn has_flag(args: List(String), flag: String) -> Bool {
  list.contains(args, flag)
}

fn task_json(task: Task, compact: Bool) -> json.Json {
  case compact {
    False -> serde.task_to_json(task)
    True ->
      json.object([
        #("id", json.string(task.id)),
        #("title", json.string(task.title)),
        #("status", json.string(serde.status_to_string(task.status))),
        #("priority", json.int(task.priority)),
        #("kind", json.string(kind_name(task.kind))),
        #("assignee", json.nullable(task.assignee, of: json.string)),
      ])
  }
}

fn matches(task: Task, spec: Spec, now: Int) -> Bool {
  { list.is_empty(spec.statuses) || list.contains(spec.statuses, task.status) }
  && { list.is_empty(spec.kinds) || list.contains(spec.kinds, task.kind) }
  && option_int_min(task.priority, spec.priority_min)
  && option_int_max(task.priority, spec.priority_max)
  && option_string(task.assignee, spec.assignee)
  && labels_any(task.labels, spec.labels_any)
  && list.all(spec.labels_all, fn(label) { list.contains(task.labels, label) })
  && deferred_matches(task, spec.deferred, now)
  && option_int_min(task.created_at, spec.created_after)
  && option_int_max(task.created_at, spec.created_before)
  && option_int_min(task.updated_at, spec.updated_after)
  && option_int_max(task.updated_at, spec.updated_before)
}

fn deferred_matches(task: Task, filter: DeferredFilter, now: Int) -> Bool {
  case filter {
    AnyDeferred -> True
    DeferredOnly -> graph.is_deferred(task, now)
    NotDeferred -> !graph.is_deferred(task, now)
  }
}

fn labels_any(labels: List(String), wanted: List(String)) -> Bool {
  list.is_empty(wanted)
  || list.any(wanted, fn(label) { list.contains(labels, label) })
}

fn option_string(actual: Option(String), expected: Option(String)) -> Bool {
  case expected {
    option.None -> True
    option.Some(value) -> actual == option.Some(value)
  }
}

fn option_int_min(actual: Int, expected: Option(Int)) -> Bool {
  case expected {
    option.None -> True
    option.Some(value) -> actual >= value
  }
}

fn option_int_max(actual: Int, expected: Option(Int)) -> Bool {
  case expected {
    option.None -> True
    option.Some(value) -> actual <= value
  }
}

fn comparator(
  field: SortField,
  direction: Direction,
) -> fn(Task, Task) -> Order {
  fn(a: Task, b: Task) {
    let order = case field {
      ById -> string.compare(a.id, b.id)
      ByPriority -> compare_int_then_id(a.priority, b.priority, a.id, b.id)
      ByCreated -> compare_int_then_id(a.created_at, b.created_at, a.id, b.id)
      ByUpdated -> compare_int_then_id(a.updated_at, b.updated_at, a.id, b.id)
    }
    case direction {
      Ascending -> order
      Descending -> reverse(order)
    }
  }
}

fn compare_int_then_id(a: Int, b: Int, aid: String, bid: String) -> Order {
  case int.compare(a, b) {
    order.Eq -> string.compare(aid, bid)
    other -> other
  }
}

fn reverse(value: Order) -> Order {
  case value {
    order.Lt -> order.Gt
    order.Eq -> order.Eq
    order.Gt -> order.Lt
  }
}

fn apply_limit(tasks: List(Task), limit: Option(Int)) -> List(Task) {
  case limit {
    option.None -> tasks
    option.Some(value) -> list.take(tasks, value)
  }
}

fn parse_int(value: String, name: String) -> Result(Int, String) {
  int.parse(value)
  |> result.map_error(fn(_) { name <> " must be an integer" })
}

fn parse_non_negative(value: String, name: String) -> Result(Int, String) {
  parse_int(value, name)
  |> result.try(fn(n) {
    case n < 0 {
      True -> Error(name <> " must be non-negative")
      False -> Ok(n)
    }
  })
}

fn sort_from_string(value: String) -> Result(SortField, String) {
  case value {
    "id" -> Ok(ById)
    "priority" -> Ok(ByPriority)
    "created" | "created_at" -> Ok(ByCreated)
    "updated" | "updated_at" -> Ok(ByUpdated)
    _ -> Error("invalid sort field: " <> value)
  }
}

fn kind_name(value: types.TaskKind) -> String {
  case value {
    DefaultTask -> "task"
    Bug -> "bug"
    Feature -> "feature"
    Epic -> "epic"
    Decision -> "decision"
    Chore -> "chore"
    Gate -> "gate"
    Wisp -> "wisp"
  }
}

fn kind_from_string(value: String) -> Result(types.TaskKind, String) {
  case value {
    "task" | "default" -> Ok(DefaultTask)
    "bug" -> Ok(Bug)
    "feature" -> Ok(Feature)
    "epic" -> Ok(Epic)
    "decision" -> Ok(Decision)
    "chore" -> Ok(Chore)
    "gate" -> Ok(Gate)
    "wisp" -> Ok(Wisp)
    _ -> Error("invalid task kind: " <> value)
  }
}
