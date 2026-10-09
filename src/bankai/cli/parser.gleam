//// CLI argument parsing helpers and response envelopes.

import bankai/serde
import bankai/types.{type RelationType, type TaskKind, Blocks, DefaultTask}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/string

pub fn envelope(result: Result(json.Json, String)) -> String {
  case result {
    Ok(data) -> json.to_string(json.object([#("ok", data)]))
    Error(message) ->
      json.to_string(json.object([#("error", json.string(message))]))
  }
}

pub fn parse_export_format(args: List(String)) -> String {
  case args {
    ["--format", "json", ..] -> "json"
    ["--format", "md", ..] -> "md"
    [_, ..rest] -> parse_export_format(rest)
    [] -> "md"
  }
}

pub fn parse_kind(args: List(String)) -> TaskKind {
  case args {
    ["--kind", value, ..] -> serde.kind_from_string(value)
    [_, ..rest] -> parse_kind(rest)
    [] -> DefaultTask
  }
}

pub fn parse_parent(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--parent", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_parent(rest)
  }
}

/// --description D: the single argv token after the flag ("" when absent).
pub fn parse_description(args: List(String)) -> String {
  case args {
    [] -> ""
    ["--description", v, ..] -> v
    [_, ..rest] -> parse_description(rest)
  }
}

pub fn parse_labels(args: List(String)) -> List(String) {
  let #(_, labels) =
    list.fold(args, #(False, []), fn(acc, a) {
      let #(want_value, labels) = acc
      case want_value, a {
        True, v -> #(False, [v, ..labels])
        False, "--label" -> #(True, labels)
        False, _ -> #(False, labels)
      }
    })
  labels
}

pub fn parse_label_filter(args: List(String)) -> Option(String) {
  case parse_labels(args) {
    [] -> option.None
    [label, ..] -> option.Some(label)
  }
}

pub fn parse_from(args: List(String)) -> Option(String) {
  case args {
    [] -> option.None
    ["--from", v, ..] -> option.Some(v)
    [_, ..rest] -> parse_from(rest)
  }
}

pub fn parse_priority(args: List(String)) -> Int {
  case args {
    ["--priority", value, ..] ->
      case int.parse(value) {
        Ok(priority) -> priority
        Error(_) -> 1
      }
    [_, ..rest] -> parse_priority(rest)
    [] -> 1
  }
}

pub fn parse_days(args: List(String)) -> Int {
  case args {
    ["--days", value, ..] ->
      case int.parse(value) {
        Ok(days) -> days
        Error(_) -> 7
      }
    [_, ..rest] -> parse_days(rest)
    [] -> 7
  }
}

pub fn parse_threshold(args: List(String), default: Float) -> Float {
  case args {
    ["--threshold", value, ..] ->
      case float.parse(value) {
        Ok(threshold) -> threshold
        Error(_) -> default
      }
    [_, ..rest] -> parse_threshold(rest, default)
    [] -> default
  }
}

pub fn parse_relation_type(args: List(String)) -> RelationType {
  case args {
    ["--type", value, ..] ->
      case serde.relation_from_string(value) {
        Ok(t) -> t
        Error(_) -> Blocks
      }
    [_, ..rest] -> parse_relation_type(rest)
    [] -> Blocks
  }
}

pub fn parse_port(args: List(String), default: Int) -> Int {
  case args {
    ["--port", value, ..] ->
      case int.parse(value) {
        Ok(port) -> port
        Error(Nil) -> default
      }
    [_, ..rest] -> parse_port(rest, default)
    [] -> default
  }
}

// ---------------------------------------------------------------------------
// Whole-command grammars (bk-57c1): parse create/update argv into typed
// records ONCE so the daemon and embedded paths share one grammar, and any
// flag outside it fails loudly instead of being silently swallowed.
// ---------------------------------------------------------------------------

pub type CreateArgs {
  CreateArgs(
    title: String,
    description: String,
    labels: List(String),
    priority: Option(String),
    parent: Option(String),
    kind: Option(String),
  )
}

pub type UpdateArgs {
  UpdateArgs(
    id: String,
    status: Option(String),
    claim: Option(String),
    force: Bool,
    labels: List(String),
    remove_labels: List(String),
    priority: Option(String),
    fence: Option(String),
    release: Bool,
    reopen: Bool,
    undefer: Bool,
    defer_until: Option(String),
    satisfy_gate: Bool,
    close: Option(String),
  )
}

fn is_flag(value: String) -> Bool {
  string.starts_with(value, "--")
}

/// `create <title> [flags]` or `create --title <title> [flags]`.
/// Whitelisted flags: --description --label --priority --parent --kind
/// --due --satisfied --expires-at --ttl --actor --reason (gate/wisp).
pub fn parse_create_args(args: List(String)) -> Result(CreateArgs, String) {
  case args {
    [] -> Error("create requires a title")
    ["--title", title, ..rest] ->
      parse_create_rest(
        rest,
        CreateArgs(title, "", [], option.None, option.None, option.None),
      )
    ["--title"] -> Error("--title requires a value")
    [title, ..rest] ->
      case is_flag(title) {
        True -> Error("unknown create argument: " <> title)
        False ->
          parse_create_rest(
            rest,
            CreateArgs(title, "", [], option.None, option.None, option.None),
          )
      }
  }
}

fn parse_create_rest(
  args: List(String),
  acc: CreateArgs,
) -> Result(CreateArgs, String) {
  case args {
    [] -> Ok(acc)
    ["--description", value, ..rest] ->
      parse_create_rest(rest, CreateArgs(..acc, description: value))
    ["--label", value, ..rest] ->
      parse_create_rest(
        rest,
        CreateArgs(..acc, labels: list.append(acc.labels, [value])),
      )
    ["--priority", value, ..rest] ->
      parse_create_rest(rest, CreateArgs(..acc, priority: option.Some(value)))
    ["--parent", value, ..rest] ->
      parse_create_rest(rest, CreateArgs(..acc, parent: option.Some(value)))
    ["--kind", value, ..rest] ->
      parse_create_rest(rest, CreateArgs(..acc, kind: option.Some(value)))
    // Gate/wisp flags: recognized, consumed, applied by downstream handlers
    // that still receive the raw argv.
    ["--due", _, ..rest] -> parse_create_rest(rest, acc)
    ["--expires-at", _, ..rest] -> parse_create_rest(rest, acc)
    ["--ttl", _, ..rest] -> parse_create_rest(rest, acc)
    ["--actor", _, ..rest] -> parse_create_rest(rest, acc)
    ["--reason", _, ..rest] -> parse_create_rest(rest, acc)
    ["--satisfied", ..rest] -> parse_create_rest(rest, acc)
    [unknown, ..] -> Error("unknown create argument: " <> unknown)
  }
}

/// `update <id> [status] [--claim [a]] [--label l]... [--priority n] ...`
/// Every recognized flag composes in one call; anything else errors loudly.
pub fn parse_update_args(args: List(String)) -> Result(UpdateArgs, String) {
  case args {
    [] -> Error("update requires a task id")
    [id, ..rest] ->
      case is_flag(id) {
        True -> Error("update requires a task id, got flag: " <> id)
        False ->
          parse_update_rest(
            rest,
            UpdateArgs(
              id: id,
              status: option.None,
              claim: option.None,
              force: False,
              labels: [],
              remove_labels: [],
              priority: option.None,
              fence: option.None,
              release: False,
              reopen: False,
              undefer: False,
              defer_until: option.None,
              satisfy_gate: False,
              close: option.None,
            ),
          )
      }
  }
}

fn parse_update_rest(
  args: List(String),
  acc: UpdateArgs,
) -> Result(UpdateArgs, String) {
  case args {
    [] -> Ok(acc)
    ["--claim", value, ..rest] ->
      case is_flag(value) {
        True ->
          parse_update_rest(
            [value, ..rest],
            UpdateArgs(..acc, claim: option.Some("agent")),
          )
        False ->
          parse_update_rest(rest, UpdateArgs(..acc, claim: option.Some(value)))
      }
    ["--claim"] -> Ok(UpdateArgs(..acc, claim: option.Some("agent")))
    ["--force", ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, force: True))
    ["--label", value, ..rest] ->
      parse_update_rest(
        rest,
        UpdateArgs(..acc, labels: list.append(acc.labels, [value])),
      )
    ["--remove-label", value, ..rest] ->
      parse_update_rest(
        rest,
        UpdateArgs(
          ..acc,
          remove_labels: list.append(acc.remove_labels, [value]),
        ),
      )
    ["--priority", value, ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, priority: option.Some(value)))
    ["--fence", value, ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, fence: option.Some(value)))
    ["--release", ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, release: True))
    ["--reopen", ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, reopen: True))
    ["--undefer", ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, undefer: True))
    ["--defer-until", value, ..rest] ->
      parse_update_rest(
        rest,
        UpdateArgs(..acc, defer_until: option.Some(value)),
      )
    ["--satisfy-gate", ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, satisfy_gate: True))
    ["--close", reason, ..rest] ->
      parse_update_rest(rest, UpdateArgs(..acc, close: option.Some(reason)))
    // Global workspace flag other commands honor; tolerated here so bare
    // `--claim --repo .` keeps meaning "claim as agent" (bk-616f test).
    ["--repo", _, ..rest] -> parse_update_rest(rest, acc)
    [word, ..rest] ->
      case is_flag(word) {
        True -> Error("unknown update argument: " <> word)
        False ->
          case acc.status {
            option.None ->
              parse_update_rest(
                rest,
                UpdateArgs(..acc, status: option.Some(word)),
              )
            option.Some(_) ->
              Error("unexpected extra update argument: " <> word)
          }
      }
  }
}
