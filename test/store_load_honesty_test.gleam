//// Regression tests for loader honesty (bk-31a4): a file that exists but
//// cannot be read must be an Error, never a silent empty store — the next
//// flush would destroy it. A missing file is still a legitimate empty
//// store (fresh workspace).

import bankai/memory
import bankai/message
import bankai/sync/jsonl
import gleam/set
import gleeunit/should
import simplifile.{FilePermissions, Read, Write}

const dir = "/tmp/bankai_load_honesty"

/// Nobody may read (0o0) — the owner included.
fn unreadable() -> simplifile.FilePermissions {
  FilePermissions(user: set.new(), group: set.new(), other: set.new())
}

/// Owner read/write, everyone else read (0o644).
fn readable() -> simplifile.FilePermissions {
  FilePermissions(
    user: set.new() |> set.insert(Read) |> set.insert(Write),
    group: set.new() |> set.insert(Read),
    other: set.new() |> set.insert(Read),
  )
}

fn setup() {
  let _ = simplifile.delete(dir)
  let _ = simplifile.create_directory_all(dir)
  Nil
}

/// An unreadable regular file: read fails, is_file is True -> Error.
fn unreadable_path(name: String) -> String {
  let path = dir <> "/" <> name
  let _ = simplifile.write("{}", to: path)
  let _ = simplifile.set_permissions(path, to: unreadable())
  path
}

fn cleanup() {
  // Restore permissions so delete works, then drop the directory.
  let _ = simplifile.set_permissions(dir <> "/tasks.jsonl", to: readable())
  let _ = simplifile.set_permissions(dir <> "/memories.jsonl", to: readable())
  let _ = simplifile.set_permissions(dir <> "/messages.jsonl", to: readable())
  let _ = simplifile.delete(dir)
  Nil
}

pub fn tasks_missing_file_is_empty_test() {
  setup()
  jsonl.load(from: dir <> "/tasks.jsonl")
  |> should.equal(Ok([]))
  cleanup()
}

pub fn tasks_unreadable_file_is_error_test() {
  setup()
  let _ = unreadable_path("tasks.jsonl")
  let assert Error(_) = jsonl.load(from: dir <> "/tasks.jsonl")
  cleanup()
}

pub fn memories_missing_file_is_empty_test() {
  setup()
  memory.load(from: dir <> "/memories.jsonl")
  |> should.equal(Ok([]))
  cleanup()
}

pub fn memories_unreadable_file_is_error_test() {
  setup()
  let _ = unreadable_path("memories.jsonl")
  let assert Error(_) = memory.load(from: dir <> "/memories.jsonl")
  cleanup()
}

pub fn messages_missing_file_is_error_free_empty_test() {
  setup()
  message.load(from: dir <> "/messages.jsonl")
  |> should.equal(Ok([]))
  cleanup()
}

pub fn messages_unreadable_file_is_error_test() {
  setup()
  let _ = unreadable_path("messages.jsonl")
  let assert Error(_) = message.load(from: dir <> "/messages.jsonl")
  cleanup()
}
