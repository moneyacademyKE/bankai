import gleeunit
import gleeunit/should
import gleam/option
import gleamunison/identity
import bankai/actors/task_actor
import bankai/builder
import bankai/types.{InProgress, Open}

pub fn main() {
  gleeunit.main()
}

fn fresh_task() {
  builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
}

pub fn get_state_returns_current_task_test() {
  let task = fresh_task()
  let assert Ok(started) = task_actor.start(task)
  let state = task_actor.get_state(started.data, 1000)

  state.id
  |> should.equal("bk-0001")
}

pub fn update_status_advances_content_hash_test() {
  let task = fresh_task()
  let assert Ok(started) = task_actor.start(task)
  let result = task_actor.update_status(started.data, InProgress, 1000)

  let updated = should.be_ok(result)
  identity.hash_equal(updated.content_hash, task.content_hash)
  |> should.be_false
  updated.status
  |> should.equal(InProgress)
}

pub fn add_relation_cycles_are_rejected_test() {
  // Existing graph: B depends on A (edge B -> A). Adding A -> B closes a cycle.
  let task_a = fresh_task()
  let assert Ok(started) = task_actor.start(task_a)
  let all_edges = [#("bk-0002", "bk-0001")]

  let result = task_actor.add_relation(started.data, "bk-0002", all_edges, 1000)

  result
  |> should.be_error
}

pub fn add_relation_acyclic_is_applied_test() {
  let task_a = fresh_task()
  let assert Ok(started) = task_actor.start(task_a)
  // No existing edges: A -> C is safe.
  let result = task_actor.add_relation(started.data, "bk-0009", [], 1000)

  let updated = should.be_ok(result)
  identity.hash_equal(updated.content_hash, task_a.content_hash)
  |> should.be_false
}
