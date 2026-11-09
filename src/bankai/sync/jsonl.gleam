//// .bankai/tasks.jsonl persistence (Git-trackable, one task per line).

import bankai/serde
import bankai/storage/store
import bankai/types.{type Task}
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// Write all tasks to a JSONL file (full rewrite — deterministic).
pub fn flush(
  tasks: List(Task),
  to path: String,
) -> Result(Nil, simplifile.FileError) {
  // BUG-09 fix: JSONL convention is one record per line, each terminated by
  // "\n" — external tools (wc -l, tail, jq) expect a trailing newline. An empty
  // task list writes an empty file (the reader yields []).
  let body =
    tasks
    |> list.map(serde.task_to_json)
    |> list.map(json.to_string)
    |> string.join("\n")

  let body = case list.is_empty(tasks) {
    True -> ""
    False -> body <> "\n"
  }

  simplifile.write(body, to: path)
}

/// Flush with an honest, named error (bk-035b): a failed durable write IS
/// the operation's error at every file-mode call site. Single owner of the
/// rendering — the `let _ =` call sites that used to discard the flush
/// Result route through here instead.
pub fn flush_report(tasks: List(Task), to path: String) -> Result(Nil, String) {
  flush(tasks, to: path)
  |> result.map_error(fn(e) {
    "could not write " <> path <> ": " <> simplifile.describe_error(e)
  })
}

/// Load tasks from a JSONL file. A missing file or empty body yields [];
/// an existing file that cannot be read is an Error, never an empty store.
/// Every non-empty record must decode and pass the content-address integrity
/// check; a corrupt snapshot is rejected rather than partially loaded.
pub fn load(from path: String) -> Result(List(Task), String) {
  case simplifile.read(from: path) {
    Ok(body) ->
      case string.trim(body) {
        "" -> Ok([])
        _ ->
          body
          |> string.split("\n")
          |> list.filter(fn(line) { string.trim(line) != "" })
          |> list.try_map(serde.task_from_json_string)
      }
    // Missing file -> empty store (fresh workspace). An existing file that
    // cannot be read is NOT an empty store: reporting [] would let the next
    // flush destroy it (bk-31a4).
    Error(e) ->
      case simplifile.is_file(path) {
        Ok(False) -> Ok([])
        _ ->
          Error(
            "tasks file exists but could not be read: " <> string.inspect(e),
          )
      }
  }
}

/// Load tasks.jsonl straight into a content-addressed Store. This is the
/// ONE owner of that composition (bk-f250): a missing file is a fresh empty
/// store, an unreadable file is an Error the caller must propagate — the
/// private cli/compact copies that re-masked it to store.new() are gone.
pub fn load_store(from path: String) -> Result(store.Store, String) {
  load(from: path) |> result.map(store.from_list)
}

/// Ensure a directory exists (for `.bankai/`).
pub fn ensure_dir(path: String) -> Result(Nil, simplifile.FileError) {
  simplifile.create_directory_all(path)
}
