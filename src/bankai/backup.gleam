//// Safe catalog, validation, preview, and restore operations for task backups.

import bankai/sync/jsonl
import bankai/types.{type Task, Blocked, InProgress, Open}
import gleam/dict
import gleam/list
import gleam/result
import gleam/string
import simplifile

pub type CatalogEntry {
  CatalogEntry(path: String, task_count: Int, valid: Bool)
}

pub type RestorePreview {
  RestorePreview(current_count: Int, backup_count: Int)
}

/// Validate that a backup exists and contains only integrity-valid tasks.
pub fn validate(path: String) -> Result(List(Task), String) {
  case simplifile.is_file(path) {
    Ok(True) -> jsonl.load(from: path)
    Ok(False) -> Error("backup not found: " <> path)
    Error(_) -> Error("backup not found: " <> path)
  }
}

/// Catalog task backups in a workspace. A workspace that does not yet exist has
/// an empty catalog; corrupt backups remain visible with `valid: False`.
pub fn catalog(workspace: String) -> Result(List(CatalogEntry), String) {
  case simplifile.read_directory(at: workspace) {
    Error(_) -> Ok([])
    Ok(entries) ->
      entries
      |> list.filter(fn(name) { string.starts_with(name, "tasks.jsonl.bak.") })
      |> list.sort(by: string.compare)
      |> list.map(fn(name) {
        let path = workspace <> "/" <> name
        case validate(path) {
          Ok(tasks) -> CatalogEntry(path, list.length(tasks), True)
          Error(_) -> CatalogEntry(path, 0, False)
        }
      })
      |> Ok
  }
}

/// Compare the validated backup with the current task store without mutating it.
pub fn preview_restore(
  workspace: String,
  path: String,
) -> Result(RestorePreview, String) {
  use backup_tasks <- result.try(validate(path))
  use current_tasks <- result.try(jsonl.load(from: workspace <> "/tasks.jsonl"))
  Ok(RestorePreview(
    current_count: list.length(current_tasks),
    backup_count: list.length(backup_tasks),
  ))
}

pub type DetailedDivergence {
  DetailedDivergence(
    current_count: Int,
    backup_count: Int,
    same_tasks: Int,
    added_in_backup: List(String),
    missing_in_backup: List(String),
    modified_in_backup: List(String),
  )
}

/// Detailed divergence comparing existing workspace tasks with candidate backup tasks.
pub fn divergence_detail(
  workspace: String,
  path: String,
) -> Result(DetailedDivergence, String) {
  use backup_tasks <- result.try(validate(path))
  let current_tasks = case jsonl.load(from: workspace <> "/tasks.jsonl") {
    Ok(tasks) -> tasks
    Error(_) -> []
  }
  let current_map =
    current_tasks
    |> list.map(fn(t) { #(t.id, t) })
    |> dict.from_list

  let backup_map =
    backup_tasks
    |> list.map(fn(t) { #(t.id, t) })
    |> dict.from_list

  let added =
    backup_tasks
    |> list.filter_map(fn(t) {
      case dict.get(current_map, t.id) {
        Error(_) -> Ok(t.id)
        Ok(_) -> Error(Nil)
      }
    })

  let missing =
    current_tasks
    |> list.filter_map(fn(t) {
      case dict.get(backup_map, t.id) {
        Error(_) -> Ok(t.id)
        Ok(_) -> Error(Nil)
      }
    })

  let modified =
    backup_tasks
    |> list.filter_map(fn(t) {
      case dict.get(current_map, t.id) {
        Ok(curr) ->
          case curr.content_hash == t.content_hash {
            False -> Ok(t.id)
            True -> Error(Nil)
          }
        Error(_) -> Error(Nil)
      }
    })

  let same_count =
    backup_tasks
    |> list.filter(fn(t) {
      case dict.get(current_map, t.id) {
        Ok(curr) -> curr.content_hash == t.content_hash
        Error(_) -> False
      }
    })
    |> list.length

  Ok(DetailedDivergence(
    current_count: list.length(current_tasks),
    backup_count: list.length(backup_tasks),
    same_tasks: same_count,
    added_in_backup: added,
    missing_in_backup: missing,
    modified_in_backup: modified,
  ))
}

/// Restore a validated backup. Validation happens before any target write.
pub fn restore(workspace: String, path: String) -> Result(Nil, String) {
  use tasks <- result.try(validate(path))
  case simplifile.create_directory_all(workspace) {
    Error(_) -> Error("could not create restore workspace: " <> workspace)
    Ok(Nil) ->
      case jsonl.flush(tasks, to: workspace <> "/tasks.jsonl") {
        Ok(Nil) -> Ok(Nil)
        Error(_) -> Error("could not replace task store")
      }
  }
}

/// Group tasks that share the same title (potential duplicates).
pub fn analyze_duplicates(tasks: List(Task)) -> List(List(Task)) {
  tasks
  |> list.group(fn(t) { t.title })
  |> dict.to_list
  |> list.filter_map(fn(pair) {
    let #(_, group) = pair
    case list.length(group) > 1 {
      True -> Ok(group)
      False -> Error(Nil)
    }
  })
}

/// Find open/in-progress/blocked tasks whose updated_at is older than the cutoff.
pub fn analyze_stale(tasks: List(Task), older_than: Int) -> List(Task) {
  tasks
  |> list.filter(fn(t) {
    case t.status {
      Open | InProgress | Blocked -> t.updated_at < older_than
      _ -> False
    }
  })
}

/// Delete all but the newest `keep` backups. Returns the number pruned.
pub fn prune(workspace: String, keep keep: Int) -> Result(Int, String) {
  case simplifile.read_directory(at: workspace) {
    Error(_) -> Ok(0)
    Ok(entries) -> {
      let backups =
        entries
        |> list.filter(fn(name) { string.starts_with(name, "tasks.jsonl.bak.") })
        |> list.sort(by: string.compare)

      let total = list.length(backups)
      case total <= keep {
        True -> Ok(0)
        False -> {
          let to_delete =
            backups
            |> list.take(total - keep)

          to_delete
          |> list.each(fn(name) {
            let _ = simplifile.delete(workspace <> "/" <> name)
            Nil
          })

          Ok(list.length(to_delete))
        }
      }
    }
  }
}
