import bankai/mnesia_store
import bankai/serde
import bankai/task_mutation.{type Mutation}
import bankai/time
import bankai/types.{type Task}
import gleam/bit_array
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import gleamunison/identity

pub fn release(workspace: String, id: String) -> Result(json.Json, String) {
  update_one(workspace, task_mutation.Release(id))
}

pub fn reopen(workspace: String, id: String) -> Result(json.Json, String) {
  update_one(workspace, task_mutation.Reopen(id))
}

pub fn undefer(workspace: String, id: String) -> Result(json.Json, String) {
  update_one(workspace, task_mutation.Undefer(id))
}

pub fn remove_label(
  workspace: String,
  id: String,
  label: String,
) -> Result(json.Json, String) {
  update_one(workspace, task_mutation.RemoveLabel(id, label))
}

fn update_one(
  workspace: String,
  mutation: Mutation,
) -> Result(json.Json, String) {
  let id = task_mutation.id(mutation)
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(previous) {
    task_mutation.apply(previous, mutation, time.now())
    |> result.try(fn(updated) {
      case updated.content_hash == previous.content_hash {
        True -> Ok(previous)
        False -> mnesia_store.replace(workspace, previous, updated)
      }
    })
  })
  |> result.map(serde.task_to_json)
}

pub fn batch(
  workspace: String,
  idempotency_key: String,
  encoded_mutations: List(String),
) -> Result(json.Json, String) {
  case idempotency_key == "", list.is_empty(encoded_mutations) {
    True, _ -> Error("batch requires a non-empty idempotency key")
    _, True -> Error("batch requires at least one mutation")
    False, False -> {
      let request_fingerprint = fingerprint(encoded_mutations)
      mnesia_store.idempotent_result(
        workspace,
        idempotency_key,
        "batch-command",
      )
      |> result.try(fn(saved) {
        case saved {
          option.Some(#(saved_fingerprint, summary)) ->
            case saved_fingerprint == request_fingerprint {
              True ->
                Ok(response(
                  idempotency_key,
                  request_fingerprint,
                  summary,
                  0,
                  True,
                ))
              False ->
                Error("idempotency key already used with different batch")
            }
          option.None ->
            encoded_mutations
            |> list.try_map(task_mutation.parse)
            |> result.try(no_duplicate_ids)
            |> result.try(fn(mutations) { plan(workspace, mutations) })
            |> result.try(fn(replacements) {
              mnesia_store.replace_many_idempotent(
                workspace,
                idempotency_key,
                request_fingerprint,
                replacements,
              )
              |> result.map(fn(summary) {
                response(
                  idempotency_key,
                  request_fingerprint,
                  summary,
                  list.length(replacements),
                  False,
                )
              })
            })
        }
      })
    }
  }
}

fn response(
  idempotency_key: String,
  request_fingerprint: String,
  summary: String,
  mutations: Int,
  replayed: Bool,
) -> json.Json {
  json.object([
    #("idempotency_key", json.string(idempotency_key)),
    #("fingerprint", json.string(request_fingerprint)),
    #("result", json.string(summary)),
    #("mutations", json.int(mutations)),
    #("replayed", json.bool(replayed)),
  ])
}

fn no_duplicate_ids(
  mutations: List(Mutation),
) -> Result(List(Mutation), String) {
  let ids = list.map(mutations, task_mutation.id)
  case list.length(ids) == list.length(list.unique(ids)) {
    True -> Ok(mutations)
    False -> Error("batch accepts at most one mutation per task")
  }
}

fn plan(
  workspace: String,
  mutations: List(Mutation),
) -> Result(List(#(Task, Task)), String) {
  mutations
  |> list.try_map(fn(mutation) {
    let id = task_mutation.id(mutation)
    mnesia_store.get_current(workspace, id)
    |> result.try(fn(previous) {
      task_mutation.apply(previous, mutation, time.now())
      |> result.map(fn(updated) { #(previous, updated) })
    })
  })
}

fn fingerprint(values: List(String)) -> String {
  values
  |> string.join("\n")
  |> bit_array.from_string
  |> identity.hash_bytes
  |> identity.hash_to_debug_string
}
