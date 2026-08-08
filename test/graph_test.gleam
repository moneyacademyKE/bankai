import bankai/builder
import bankai/graph
import bankai/types.{
  Blocks, Closed, Completed, ConditionalBlocks, InProgress, Open, RelatesTo,
  Relationship, WaitsFor,
}
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn chain() {
  let a =
    builder.build("A", "a", "d", Open, option.None, 1, 1, 1, [
      Relationship("B", Blocks),
    ])
  let b =
    builder.build("B", "b", "d", Open, option.None, 1, 1, 1, [
      Relationship("C", Blocks),
    ])
  let c = builder.build("C", "c", "d", Open, option.None, 1, 1, 1, [])
  [a, b, c]
}

pub fn would_cycle_detects_back_edge_test() {
  graph.would_cycle(graph.all_edges(chain()), #("C", "A")) |> should.be_true
}

pub fn would_cycle_allows_acyclic_test() {
  graph.would_cycle(graph.all_edges(chain()), #("C", "D")) |> should.be_false
}

pub fn would_cycle_self_loop_test() {
  graph.would_cycle([], #("A", "A")) |> should.be_true
}

pub fn ready_only_returns_unblocked_active_test() {
  let tasks =
    chain()
    |> list.map(fn(t) {
      case t.id {
        "C" -> builder.build("C", "c", "d", Completed, option.None, 1, 1, 1, [])
        _ -> t
      }
    })
  let ready_ids = graph.ready_tasks(tasks) |> list.map(fn(t) { t.id })
  list.contains(ready_ids, "B") |> should.be_true
  list.contains(ready_ids, "A") |> should.be_false
  list.contains(ready_ids, "C") |> should.be_false
}

pub fn non_blocks_relations_do_not_block_test() {
  let a =
    builder.build("A", "a", "d", InProgress, option.None, 1, 1, 1, [
      Relationship("B", RelatesTo),
    ])
  let b = builder.build("B", "b", "d", Open, option.None, 1, 1, 1, [])
  graph.ready_tasks([a, b])
  |> list.map(fn(t) { t.id })
  |> list.contains("A")
  |> should.be_true
}

pub fn topological_sort_dependencies_first_test() {
  graph.topological_sort(chain()) |> should.equal(["C", "B", "A"])
}

pub fn closed_blocker_does_not_satisfy_dependency_test() {
  let c = builder.build("C", "c", "d", Closed, option.None, 1, 1, 1, [])
  let b =
    builder.build("B", "b", "d", Open, option.None, 1, 1, 1, [
      Relationship("C", Blocks),
    ])
  graph.ready_tasks([b, c])
  |> list.map(fn(t) { t.id })
  |> list.contains("B")
  |> should.be_false
}

pub fn waits_for_and_conditional_blocks_are_blocking_test() {
  let blocker =
    builder.build("B", "blocker", "d", Open, option.None, 1, 1, 1, [])
  let waits =
    builder.build("W", "waits", "d", Open, option.None, 1, 1, 1, [
      Relationship("B", WaitsFor),
    ])
  let conditional =
    builder.build("C", "conditional", "d", Open, option.None, 1, 1, 1, [
      Relationship("B", ConditionalBlocks),
    ])
  let ready_ids =
    graph.ready_tasks([waits, conditional, blocker])
    |> list.map(fn(task) { task.id })
  list.contains(ready_ids, "W") |> should.be_false
  list.contains(ready_ids, "C") |> should.be_false
  list.contains(ready_ids, "B") |> should.be_true
}

pub fn waits_for_and_conditional_blocks_cycle_test() {
  graph.would_cycle([#("A", "B"), #("B", "C")], #("C", "A")) |> should.be_true
}
