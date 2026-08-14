import bankai/backup
import bankai/builder
import bankai/sync/jsonl
import bankai/types.{type Task, Open}
import gleam/list
import gleam/option.{None}
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

fn make_task(id: String, title: String, updated_at: Int) -> Task {
  builder.build(id, title, "", Open, None, 1, updated_at, updated_at, [])
}

fn write_backup(workspace: String, name: String, tasks: List(Task)) -> String {
  let path = workspace <> "/" <> name
  let assert Ok(Nil) = simplifile.create_directory_all(workspace)
  let assert Ok(Nil) = jsonl.flush(tasks, to: path)
  path
}

fn wipe(dir: String) -> Nil {
  let _ = simplifile.delete(dir)
  Nil
}

// --- Existing negative tests ---

pub fn missing_backup_is_rejected_before_restore_test() {
  let workspace = "/tmp/bankai_backup_lifecycle_missing"
  let path = workspace <> "/tasks.jsonl.bak.missing"

  backup.validate(path)
  |> should.be_error
  backup.preview_restore(workspace, path)
  |> should.be_error
  backup.restore(workspace, path)
  |> should.be_error
}

pub fn catalog_of_missing_workspace_is_empty_test() {
  backup.catalog("/tmp/bankai_backup_catalog_missing")
  |> should.be_ok
}

// --- Positive catalog ---

pub fn catalog_finds_valid_backups_test() {
  let workspace = "/tmp/bankai_backup_catalog_positive"
  wipe(workspace)
  let tasks = [
    make_task("bk-001", "task one", 1000),
    make_task("bk-002", "task two", 2000),
  ]
  let _ = write_backup(workspace, "tasks.jsonl.bak.1000", tasks)
  let _ = write_backup(workspace, "tasks.jsonl.bak.2000", tasks)

  let assert Ok(entries) = backup.catalog(workspace)
  list.length(entries)
  |> should.equal(2)

  entries
  |> list.each(fn(e) {
    e.valid
    |> should.be_true
    e.task_count
    |> should.equal(2)
  })
  wipe(workspace)
}

pub fn catalog_shows_corrupt_backups_as_invalid_test() {
  let workspace = "/tmp/bankai_backup_catalog_corrupt"
  wipe(workspace)
  let assert Ok(Nil) = simplifile.create_directory_all(workspace)
  let corrupt_path = workspace <> "/tasks.jsonl.bak.corrupt"
  let assert Ok(Nil) =
    simplifile.write(to: corrupt_path, contents: "not json at all\n")
  let valid_path = workspace <> "/tasks.jsonl.bak.valid"
  let assert Ok(Nil) =
    jsonl.flush([make_task("bk-001", "ok", 1000)], to: valid_path)

  let assert Ok(entries) = backup.catalog(workspace)
  list.length(entries)
  |> should.equal(2)

  let corrupt = list.find(entries, fn(e) { e.path == corrupt_path })
  case corrupt {
    Ok(e) -> {
      e.valid
      |> should.be_false
    }
    Error(_) -> should.fail()
  }
  wipe(workspace)
}

// --- Positive preview ---

pub fn preview_reports_count_divergence_test() {
  let workspace = "/tmp/bankai_backup_preview"
  wipe(workspace)
  let assert Ok(Nil) = simplifile.create_directory_all(workspace)

  let backup_tasks = [
    make_task("bk-001", "one", 1000),
    make_task("bk-002", "two", 2000),
    make_task("bk-003", "three", 3000),
  ]
  let backup_path =
    write_backup(workspace, "tasks.jsonl.bak.1000", backup_tasks)

  let current_tasks = [make_task("bk-001", "one", 1000)]
  let assert Ok(Nil) =
    jsonl.flush(current_tasks, to: workspace <> "/tasks.jsonl")

  let assert Ok(preview) = backup.preview_restore(workspace, backup_path)
  preview.current_count
  |> should.equal(1)
  preview.backup_count
  |> should.equal(3)
  wipe(workspace)
}

// --- Positive restore ---

pub fn restore_replaces_store_with_backup_test() {
  let workspace = "/tmp/bankai_backup_restore"
  wipe(workspace)
  let assert Ok(Nil) = simplifile.create_directory_all(workspace)

  let backup_tasks = [
    make_task("bk-001", "one", 1000),
    make_task("bk-002", "two", 2000),
  ]
  let backup_path =
    write_backup(workspace, "tasks.jsonl.bak.1000", backup_tasks)

  let current_tasks = [make_task("bk-099", "old", 500)]
  let assert Ok(Nil) =
    jsonl.flush(current_tasks, to: workspace <> "/tasks.jsonl")

  let assert Ok(Nil) = backup.restore(workspace, backup_path)

  let assert Ok(restored) = jsonl.load(from: workspace <> "/tasks.jsonl")
  list.length(restored)
  |> should.equal(2)

  let ids = list.map(restored, fn(t) { t.id })
  list.contains(ids, "bk-001")
  |> should.be_true
  list.contains(ids, "bk-002")
  |> should.be_true
  list.contains(ids, "bk-099")
  |> should.be_false
  wipe(workspace)
}

// --- Dedup ---

pub fn analyze_duplicates_finds_title_collisions_test() {
  let tasks = [
    make_task("bk-001", "Fix login bug", 1000),
    make_task("bk-002", "Fix login bug", 2000),
    make_task("bk-003", "Unique task", 3000),
  ]
  let groups = backup.analyze_duplicates(tasks)
  list.length(groups)
  |> should.equal(1)

  let assert Ok(group) = list.first(groups)
  list.length(group)
  |> should.equal(2)
}

pub fn analyze_duplicates_ignores_unique_titles_test() {
  let tasks = [
    make_task("bk-001", "Alpha", 1000),
    make_task("bk-002", "Beta", 2000),
  ]
  backup.analyze_duplicates(tasks)
  |> list.length
  |> should.equal(0)
}

// --- Stale ---

pub fn analyze_stale_finds_old_open_tasks_test() {
  let tasks = [
    make_task("bk-001", "Old task", 1000),
    make_task("bk-002", "Fresh task", 999_999_999),
  ]
  let stale = backup.analyze_stale(tasks, 5000)
  list.length(stale)
  |> should.equal(1)

  let assert Ok(s) = list.first(stale)
  s.id
  |> should.equal("bk-001")
}

// --- Prune ---

pub fn prune_removes_old_backups_keeping_newest_test() {
  let workspace = "/tmp/bankai_backup_prune"
  wipe(workspace)
  let tasks = [make_task("bk-001", "task", 1000)]
  let _ = write_backup(workspace, "tasks.jsonl.bak.1000", tasks)
  let _ = write_backup(workspace, "tasks.jsonl.bak.2000", tasks)
  let _ = write_backup(workspace, "tasks.jsonl.bak.3000", tasks)

  let assert Ok(pruned) = backup.prune(workspace, keep: 1)
  pruned
  |> should.equal(2)

  let assert Ok(entries) = backup.catalog(workspace)
  list.length(entries)
  |> should.equal(1)
  wipe(workspace)
}

pub fn prune_with_fewer_backups_than_keep_is_noop_test() {
  let workspace = "/tmp/bankai_backup_prune_noop"
  wipe(workspace)
  let tasks = [make_task("bk-001", "task", 1000)]
  let _ = write_backup(workspace, "tasks.jsonl.bak.1000", tasks)

  let assert Ok(pruned) = backup.prune(workspace, keep: 3)
  pruned
  |> should.equal(0)
  wipe(workspace)
}
