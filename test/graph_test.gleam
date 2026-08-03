import bankai/builder
import bankai/graph
import bankai/types.{
  Blocks, Closed, Completed, InProgress, Open, RelatesTo, Relationship,
}
import gleam/list
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

/// A (->B) B(->C) C : linear chain of Blocks.
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
  // edges: A->B, B->C. Adding C->A closes A->B->C->A cycle.
  let edges = graph.all_edges(chain())
  graph.would_cycle(edges, #("C", "A"))
  |> should.be_true
}

pub fn would_cycle_allows_acyclic_test() {
  let edges = graph.all_edges(chain())
  graph.would_cycle(edges, #("C", "D"))
  |> should.be_false
}

pub fn would_cycle_self_loop_test() {
  graph.would_cycle([], #("A", "A"))
  |> should.be_true
}

pub fn ready_only_returns_unblocked_active_test() {
  // B is blocked by C; C is Completed -> B becomes ready. A blocked by B (Open) -> not ready.
  let tasks =
    chain()
    |> list.map(fn(t) {
      case t.id {
        "C" -> builder.build("C", "c", "d", Completed, option.None, 1, 1, 1, [])
        _ -> t
      }
    })

  let ready = graph.ready_tasks(tasks)
  let ready_ids = ready |> list.map(fn(t) { t.id })

  // B is ready (blocker C is Completed). A is not (B is Open). C is done.
  list.contains(ready_ids, "B")
  |> should.be_true
  list.contains(ready_ids, "A")
  |> should.be_false
  list.contains(ready_ids, "C")
  |> should.be_false
}

pub fn non_blocks_relations_do_not_block_test() {
  // A RelatesTo B should not block A even if B is not done.
  let a =
    builder.build("A", "a", "d", InProgress, option.None, 1, 1, 1, [
      Relationship("B", RelatesTo),
    ])
  let b = builder.build("B", "b", "d", Open, option.None, 1, 1, 1, [])
  let ready = graph.ready_tasks([a, b])
  let ready_ids = ready |> list.map(fn(t) { t.id })

  list.contains(ready_ids, "A")
  |> should.be_true
}

pub fn topological_sort_dependencies_first_test() {
  // chain A->B->C (A depends on B depends on C): only valid order is C, B, A.
  graph.topological_sort(chain())
  |> should.equal(["C", "B", "A"])
}

/// BUG-03 regression: a Closed (won't-do) blocker does NOT satisfy a Blocks
/// dependency — only Completed does. B blocked by Closed-C must stay blocked.
pub fn closed_blocker_does_not_satisfy_dependency_test() {
  let c = builder.build("C", "c", "d", Closed, option.None, 1, 1, 1, [])
  let b =
    builder.build("B", "b", "d", Open, option.None, 1, 1, 1, [
      Relationship("C", Blocks),
    ])
  let ready_ids = graph.ready_tasks([b, c]) |> list.map(fn(t) { t.id })

  list.contains(ready_ids, "B")
  |> should.be_false
}
