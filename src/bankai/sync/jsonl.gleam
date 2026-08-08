//// .bankai/tasks.jsonl persistence (Git-trackable, one task per line).

import bankai/serde
import bankai/types.{type Task}
import gleam/json
import gleam/list
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

/// Load tasks from a JSONL file. A missing file or empty body yields [].
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
    Error(_) -> Ok([])
    // missing file -> empty store
  }
}

/// Ensure a directory exists (for `.bankai/`).
pub fn ensure_dir(path: String) -> Result(Nil, simplifile.FileError) {
  simplifile.create_directory_all(path)
}
