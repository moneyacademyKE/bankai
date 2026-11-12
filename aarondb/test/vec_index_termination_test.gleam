//// bk-86b0 FIX 2: greedy_search must stop when its results stop
//// changing. On degenerate (all-equal-score) corpora the strict
//// best < furthest stop never fires and the frontier keeps churning:
//// ~100 rounds of full-candidate dot products per search — the boot
//// wedge class. These tests pin bounded work, not just termination.

import aarondb/fact
import aarondb/vec_index
import gleam/int
import gleam/io
import gleam/list
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

@external(erlang, "aarondb_test_ffi", "reductions")
fn reductions() -> Int

/// An index whose every node holds the SAME vector: all dot products
/// are equal, the strict score-stop can never fire.
fn degenerate_index(n: Int) -> vec_index.VecIndex {
  int.range(
    1,
    n + 1,
    vec_index.new_with_config(vec_index.deterministic_config(list.repeat(0, n))),
    fn(acc, i) {
      let assert fact.Uid(entity) =
        fact.deterministic_uid(#("degenerate", int.to_string(i)))
      vec_index.insert(acc, entity, [1.0, 0.0, 0.0, 0.0])
    },
  )
}

/// Work guard: searching a 48-node degenerate corpus must cost a
/// small, bounded number of reductions. Before the fix the search
/// burns its whole 100-round budget re-scoring the frontier.
pub fn degenerate_search_work_is_bounded_test() {
  let idx = degenerate_index(48)
  let before = reductions()
  let results = vec_index.search(idx, [1.0, 0.0, 0.0, 0.0], 0.0, 10)
  let work = reductions() - before
  list.length(results) |> should.equal(10)
  io.println("degenerate search reductions: " <> int.to_string(work))
  // Calibrated against the measured pre/post-fix costs; see commit.
  should.be_true(work < 40_000)
}

/// Recall sanity: a varied corpus still returns the true nearest
/// neighbor first — the termination fix must not eat recall.
pub fn varied_corpus_nearest_neighbor_test() {
  let vectors = [
    #("a", [1.0, 0.0]),
    #("b", [0.0, 1.0]),
    #("c", [0.6, 0.8]),
    #("d", [-1.0, 0.0]),
    #("e", [0.0, -1.0]),
    #("f", [0.8, 0.6]),
  ]
  let idx =
    list.fold(
      vectors,
      vec_index.new_with_config(
        vec_index.deterministic_config(list.repeat(0, 6)),
      ),
      fn(acc, pair) {
        let #(name, vec) = pair
        let assert fact.Uid(entity) = fact.deterministic_uid(#("varied", name))
        vec_index.insert(acc, entity, vec)
      },
    )
  let assert [best, ..] = vec_index.search(idx, [0.0, 1.0], -1.0, 3)
  let assert fact.Uid(expected) = fact.deterministic_uid(#("varied", "b"))
  should.equal(best.entity, expected)
}

/// The insert path runs greedy_search per layer per node: a fully
/// degenerate build followed by a search must still answer correctly.
pub fn degenerate_build_then_search_test() {
  let idx = degenerate_index(48)
  let results = vec_index.search(idx, [1.0, 0.0, 0.0, 0.0], 0.0, 10)
  list.length(results) |> should.equal(10)
}
