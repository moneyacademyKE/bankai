//// Product-facing mobile-rule service.
////
//// This module composes durable local rule records with the pure isolated
//// Gleamunison evaluator. It never mutates a task: an optional task reference
//// is serialized into an immutable bounded input view only.

import bankai/mnesia_store
import bankai/rules/registry
import bankai/rules/store
import bankai/serde
import bankai/time
import gleam/json
import gleam/option.{type Option}
import gleam/result
import gleam/string
import gleamunison/identity

const max_source_chars = 16_384

const max_name_chars = 256

pub fn register(
  workspace: String,
  name: String,
  source: String,
) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) {
    case
      string.length(name) > max_name_chars
      || string.length(source) > max_source_chars
    {
      True -> Error("rule name or source exceeds the bounded artifact limit")
      False ->
        store.register(workspace, name, source)
        |> result.map(fn(hash) {
          json.object([
            #("hash", json.string(hash)),
            #("name", json.string(name)),
            #("approved", json.bool(False)),
          ])
        })
    }
  })
}

pub fn list(workspace: String) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) { store.list(workspace) })
  |> result.map(fn(artifacts) {
    json.array(artifacts, of: store.artifact_to_json)
  })
}

pub fn show(workspace: String, hash: String) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) {
    store.get(workspace, hash)
    |> result.try(fn(rule) {
      let #(name, source) = rule
      store.is_approved(workspace, hash)
      |> result.map(fn(approved) {
        json.object([
          #("hash", json.string(hash)),
          #("name", json.string(name)),
          #("source", json.string(source)),
          #("approved", json.bool(approved)),
        ])
      })
    })
  })
}

pub fn approve(workspace: String, hash: String) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) { store.approve(workspace, hash) })
  |> result.try(fn(_) { show(workspace, hash) })
}

pub fn revoke(workspace: String, hash: String) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) { store.revoke(workspace, hash) })
  |> result.try(fn(_) { show(workspace, hash) })
}

/// `options` accepts only `--caller <name>` and `--task <id>`. A task is read
/// once and encoded as immutable JSON; the evaluator gets no database handle.
pub fn evaluate(
  workspace: String,
  hash: String,
  options: List(String),
) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) { parse_eval_options(options, "cli", option.None) })
  |> result.try(fn(parsed) {
    let #(caller, task_id) = parsed
    store.get(workspace, hash)
    |> result.try(fn(rule) {
      let #(_, source) = rule
      task_view(workspace, task_id)
      |> result.try(fn(view) {
        let #(input_json, task_ref, task_hash) = view
        let input_hash = store.source_hash(input_json)
        let started = time.now()
        let evaluated = case store.is_approved(workspace, hash) {
          Ok(True) ->
            registry.eval_source_with_input(
              source,
              input_json,
              registry.default_eval_timeout_ms,
            )
          Ok(False) -> Error("rule not approved (allow-list denied)")
          Error(message) -> Error(message)
        }
        let duration_ns = time.now() - started
        persist_outcome(
          workspace,
          hash,
          caller,
          input_hash,
          task_ref,
          task_hash,
          duration_ns,
          evaluated,
        )
      })
    })
  })
}

pub fn audits(workspace: String, hash: String) -> Result(json.Json, String) {
  prepare(workspace)
  |> result.try(fn(_) { store.audits(workspace, hash) })
  |> result.map(fn(entries) { json.array(entries, of: store.audit_to_json) })
}

fn prepare(workspace: String) -> Result(Nil, String) {
  mnesia_store.init(workspace)
  |> result.try(fn(_) { store.init(workspace) })
}

fn persist_outcome(
  workspace: String,
  hash: String,
  caller: String,
  input_hash: String,
  task_id: String,
  task_hash: String,
  duration_ns: Int,
  evaluated: Result(String, String),
) -> Result(json.Json, String) {
  case evaluated {
    Ok(value) ->
      store.append_audit(
        workspace,
        hash,
        caller,
        input_hash,
        task_id,
        task_hash,
        duration_ns,
        "ok",
        value,
      )
      |> result.map(fn(sequence) {
        json.object([
          #("hash", json.string(hash)),
          #("input_hash", json.string(input_hash)),
          #("result", json.string(value)),
          #("audit_sequence", json.int(sequence)),
        ])
      })
    Error(message) ->
      store.append_audit(
        workspace,
        hash,
        caller,
        input_hash,
        task_id,
        task_hash,
        duration_ns,
        "error",
        message,
      )
      |> result.try(fn(_) { Error(message) })
  }
}

fn parse_eval_options(
  args: List(String),
  caller: String,
  task_id: Option(String),
) -> Result(#(String, Option(String)), String) {
  case args {
    [] -> Ok(#(caller, task_id))
    ["--caller", value, ..rest] -> parse_eval_options(rest, value, task_id)
    ["--task", value, ..rest] ->
      parse_eval_options(rest, caller, option.Some(value))
    _ -> Error("rule eval accepts only --caller <name> and --task <id>")
  }
}

fn task_view(
  workspace: String,
  task_id: Option(String),
) -> Result(#(String, String, String), String) {
  case task_id {
    option.None -> Ok(#("{\"version\":1,\"task\":null}", "", ""))
    option.Some(id) ->
      mnesia_store.get_current(workspace, id)
      |> result.map(fn(task) {
        let task_json = serde.task_to_json_string(task)
        #(
          "{\"version\":1,\"task\":" <> task_json <> "}",
          id,
          identity.hash_to_debug_string(task.content_hash),
        )
      })
  }
}
