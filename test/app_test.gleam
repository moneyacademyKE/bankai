import gleeunit
import gleeunit/should
import gleam/erlang/process
import gleam/option
import gleamunison/identity
import bankai/actors/task_actor
import bankai/app
import bankai/builder
import bankai/store_actor
import bankai/types.{Open}

pub fn main() {
  gleeunit.main()
}

fn fresh_task() {
  builder.build("bk-0001", "Write spec", "desc", Open, option.None, 1, 1000, 1000, [])
}

pub fn app_boots_and_store_responds_test() {
  let assert Ok(started) = app.start([])
  let subj = app.store_subject(started)

  store_actor.list_tasks(subj, 1000)
  |> should.equal([])
}

pub fn create_then_get_by_id_test() {
  let assert Ok(started) = app.start([])
  let subj = app.store_subject(started)
  let task = fresh_task()

  store_actor.create(subj, task, 1000)
  |> should.equal(Nil)

  let found = store_actor.get_by_id(subj, "bk-0001", 1000)
  let t = should.be_ok(found)
  t.title
  |> should.equal("Write spec")
}

pub fn task_actor_state_restored_from_store_after_kill_test() {
  let task = fresh_task()
  let assert Ok(started) = app.start([task])

  // Spawn a task actor, read its state.
  let assert Ok(actor1) = app.spawn_task_actor(started, "bk-0001", 1000)
  let before = task_actor.get_state(actor1.data, 1000)

  // Unlink so killing the actor doesn't propagate to this test process, then
  // kill it. The durable store survives.
  process.unlink(actor1.pid)
  process.kill(actor1.pid)

  // Re-spawn from the durable store; state must match.
  let assert Ok(actor2) = app.spawn_task_actor(started, "bk-0001", 1000)
  let restored = task_actor.get_state(actor2.data, 1000)

  restored.id
  |> should.equal(before.id)
  identity.hash_equal(restored.content_hash, before.content_hash)
  |> should.be_true
}
