//// Phase 2 — full-text search via aarondb's BM25 index.

import bankai/aarondb_bridge
import gleam/list
import gleeunit/should

pub fn search_matches_only_token_docs_test() {
  let docs = [
    #("task", "bk-auth", "implement the authentication module"),
    #("task", "bk-ui", "redesign the dashboard layout"),
  ]
  let results = aarondb_bridge.search(docs, "authentication")
  let ids =
    list.map(results, fn(r) {
      let #(_, id, _) = r
      id
    })
  // only the auth task contains the "authentication" token
  ids |> should.equal(["bk-auth"])
}

pub fn search_ranks_higher_freq_first_test() {
  let docs = [
    #("task", "bk-low", "authentication"),
    #("task", "bk-high", "authentication authentication authentication"),
  ]
  let results = aarondb_bridge.search(docs, "authentication")
  // both match; higher term frequency ranks first
  let ordered = case results {
    [#(_, "bk-high", _), #(_, "bk-low", _), ..] -> True
    _ -> False
  }
  ordered |> should.equal(True)
}

pub fn search_no_match_returns_empty_test() {
  let docs = [#("task", "bk-1", "write the database migration")]
  aarondb_bridge.search(docs, "authentication") |> should.equal([])
}
