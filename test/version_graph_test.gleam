//// version_graph.merge_base (bk-98c7): the fork point of two divergent
//// heads — the maximal shared ancestor. Exactly one for a clean fork,
//// none for criss-cross or unrelated histories; never an invented pick.
//// The conflict-record path derives the durable `base=` token from this.

import bankai/version_graph
import gleam/option
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn merge_base_of_a_clean_fork_is_the_shared_parent_test() {
  let graph = version_graph.graph([#("l", ["b"]), #("r", ["b"]), #("b", [])])
  version_graph.merge_base(graph, "l", "r")
  |> should.equal(option.Some("b"))
}

pub fn merge_base_of_a_one_sided_chain_is_the_last_shared_state_test() {
  // The fork is lop-sided: one side advanced twice, the other once. The
  // base is still where they last agreed.
  let graph =
    version_graph.graph([#("l", ["b2"]), #("b2", ["b"]), #("r", ["b"])])
  version_graph.merge_base(graph, "l", "r")
  |> should.equal(option.Some("b"))
}

pub fn merge_base_is_absent_when_histories_share_nothing_test() {
  let graph = version_graph.graph([#("l", ["b"]), #("r", ["c"])])
  version_graph.merge_base(graph, "l", "r")
  |> should.equal(option.None)
}

pub fn merge_base_is_absent_on_a_criss_cross_test() {
  // Two merges of the same pair of branches: x and y both descend from l
  // AND r, so the shared history has two maximal elements and no single
  // fork point exists. The honest answer is None, not an arbitrary pick —
  // Dolt synthesises a virtual base here; Bankai records the absence.
  let graph =
    version_graph.graph([
      #("l", ["b"]),
      #("r", ["b"]),
      #("x", ["l", "r"]),
      #("y", ["r", "l"]),
    ])
  version_graph.merge_base(graph, "x", "y")
  |> should.equal(option.None)
}

pub fn merge_base_of_degenerate_input_does_not_invent_a_base_test() {
  // classify answers Identical before merge_base is ever consulted, but
  // degenerate input must still not invent a fork point.
  let graph = version_graph.graph([#("l", ["b"]), #("r", ["b"])])
  version_graph.merge_base(graph, "l", "l")
  |> should.equal(option.Some("b"))
}
