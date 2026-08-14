//// CLI argument parsing helpers and response envelopes.

import bankai/serde
import bankai/types.{type RelationType, type TaskKind, Blocks, DefaultTask}
import gleam/float
import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option}

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
