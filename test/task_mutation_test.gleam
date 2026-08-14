import bankai/builder
import bankai/relations
import bankai/task_mutation
import bankai/types.{InProgress, Open}
import gleam/list
import gleam/option
import gleamunison/identity
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn fresh_task() {
  builder.build(
    "bk-0001",
    "Write spec",
    "desc",
    Open,
    option.None,
    1,
    1000,
    1000,
    [],
  )
}

pub fn update_status_advances_content_hash_test() {
  let task = fresh_task()
  let updated =
    should.be_ok(task_mutation.apply(
      task,
      task_mutation.SetStatus(task.id, InProgress),
      1000,
    ))

  identity.hash_equal(updated.content_hash, task.content_hash)
  |> should.be_false
  updated.status
  |> should.equal(InProgress)
}

pub fn add_relation_acyclic_is_applied_test() {
  let task_a = fresh_task()
  let updated =
    should.be_ok(relations.add(task_a, "bk-0009", types.Blocks, [], 1000))

  identity.hash_equal(updated.content_hash, task_a.content_hash)
  |> should.be_false
}

pub fn add_relation_dedup_is_a_noop_test() {
  let task = fresh_task()
  let once =
    should.be_ok(relations.add(task, "bk-0099", types.Blocks, [], 1000))
  let twice =
    should.be_ok(relations.add(once, "bk-0099", types.Blocks, [], 1000))

  identity.hash_equal(twice.content_hash, once.content_hash)
  |> should.be_true
  list.length(twice.relationships)
  |> should.equal(1)
}
