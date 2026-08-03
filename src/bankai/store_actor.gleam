//// The supervised Store actor — the durable source of truth.
////
//// Wraps bankai/storage/store behind a gleam_otp/actor so task state survives
//// TaskActor crashes (task actors are ephemeral; the store is permanent).
//// Registered under a process Name so it can be supervised AND addressed.

import bankai/graph
import bankai/storage/store.{type Store}
import bankai/types.{type Task}
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type StoreMsg {
  Create(task: Task, reply_to: Subject(Nil))
  GetById(id: String, reply_to: Subject(Result(Task, Nil)))
  GetByHex(hex: String, reply_to: Subject(Result(Task, Nil)))
  List(reply_to: Subject(List(Task)))
  Ready(reply_to: Subject(List(Task)))
  Count(reply_to: Subject(Int))
}

fn handle(state: Store, msg: StoreMsg) -> actor.Next(Store, StoreMsg) {
  case msg {
    Create(task, reply_to) -> {
      process.send(reply_to, Nil)
      actor.continue(store.put(state, task))
    }
    GetById(id, reply_to) -> {
      process.send(reply_to, store.find_by_id(state, id))
      actor.continue(state)
    }
    GetByHex(hex, reply_to) -> {
      process.send(reply_to, store.get_by_hex(state, hex))
      actor.continue(state)
    }
    List(reply_to) -> {
      process.send(reply_to, store.list(state))
      actor.continue(state)
    }
    Ready(reply_to) -> {
      process.send(reply_to, graph.ready_tasks(store.current_tasks(state)))
      actor.continue(state)
    }
    Count(reply_to) -> {
      process.send(reply_to, store.size(state))
      actor.continue(state)
    }
  }
}

pub fn start(
  initial: Store,
) -> Result(actor.Started(Subject(StoreMsg)), actor.StartError) {
  actor.new(initial)
  |> actor.on_message(handle)
  |> actor.start()
}

pub fn start_named(
  name: process.Name(StoreMsg),
  initial: Store,
) -> Result(actor.Started(Subject(StoreMsg)), actor.StartError) {
  actor.new(initial)
  |> actor.named(name)
  |> actor.on_message(handle)
  |> actor.start()
}

// --- synchronous call helpers ---

pub fn create(subject: Subject(StoreMsg), task: Task, timeout_ms: Int) -> Nil {
  actor.call(subject, waiting: timeout_ms, sending: fn(r) { Create(task, r) })
}

pub fn get_by_id(
  subject: Subject(StoreMsg),
  id: String,
  timeout_ms: Int,
) -> Result(Task, Nil) {
  actor.call(subject, waiting: timeout_ms, sending: fn(r) { GetById(id, r) })
}

pub fn get_by_hex(
  subject: Subject(StoreMsg),
  hex: String,
  timeout_ms: Int,
) -> Result(Task, Nil) {
  actor.call(subject, waiting: timeout_ms, sending: fn(r) { GetByHex(hex, r) })
}

pub fn list_tasks(subject: Subject(StoreMsg), timeout_ms: Int) -> List(Task) {
  actor.call(subject, waiting: timeout_ms, sending: fn(r) { List(r) })
}

pub fn ready(subject: Subject(StoreMsg), timeout_ms: Int) -> List(Task) {
  actor.call(subject, waiting: timeout_ms, sending: fn(r) { Ready(r) })
}
