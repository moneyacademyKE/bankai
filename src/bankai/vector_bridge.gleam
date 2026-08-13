//// Vector retrieval over aarondb's HNSW index.
////
//// Mnesia is Bankai's source of truth. This module builds a short-lived index
//// from Bankai documents for one command, keeping aarondb behind a Bankai-shaped
//// result type and the embedding backend behind bankai/embed.
////
//// The index topology is deliberately deterministic. The managed projection is
//// keyed by the committed Mnesia offset, so queries reuse a daemon-local HNSW
//// graph until committed membership changes; direct `search` stays available
//// for finite-corpus tests and one-shot callers.

import aarondb/fact
import aarondb/projection_index
import aarondb/vec_index
import bankai/embed
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/order
import gleam/result
import gleam/string

pub type Document {
  Document(kind: String, id: String, text: String)
}

pub type Match {
  Match(kind: String, id: String, score: Float)
}

@external(erlang, "bankai_vector_projection_ffi", "search")
fn ffi_projected_search(
  workspace: String,
  offset: Int,
  documents: List(#(String, String, String)),
  query: String,
  threshold: Float,
  limit: Int,
) -> Result(List(#(String, String, Float)), String)

@external(erlang, "bankai_vector_projection_ffi", "exact_search")
fn ffi_projected_exact_search(
  workspace: String,
  offset: Int,
  documents: List(#(String, String, String)),
  query: String,
  threshold: Float,
  limit: Int,
) -> Result(List(#(String, String, Float)), String)

@external(erlang, "bankai_vector_projection_ffi", "status")
fn ffi_projection_status(
  workspace: String,
) -> Result(#(Int, Int, String, Int), String)

@external(erlang, "bankai_vector_projection_ffi", "reset_workspace")
fn ffi_reset_projection(workspace: String) -> Result(Nil, String)

pub type ProjectionStatus {
  ProjectionStatus(
    last_applied_offset: Int,
    document_count: Int,
    health: projection_index.Health,
    generation: Int,
  )
}

/// Query the managed daemon-local HNSW projection at a committed source offset.
/// Reusing an identical offset never rebuilds the graph; an offset advance
/// produces a fresh deterministic generation before results are returned.
pub fn projected_search(
  workspace: String,
  offset: Int,
  docs: List(Document),
  query: String,
  threshold: Float,
  limit: Int,
) -> Result(List(Match), String) {
  case string.trim(query), limit <= 0 {
    "", _ -> Ok([])
    _, True -> Ok([])
    _, False ->
      ffi_projected_search(
        workspace,
        offset,
        document_rows(docs),
        query,
        threshold,
        limit,
      )
      |> result.map(matches_from_rows)
  }
}

/// Exact oracle over the same managed projection corpus. It exists solely for
/// verification and benchmark parity; user-facing commands use HNSW.
pub fn projected_exact_search(
  workspace: String,
  offset: Int,
  docs: List(Document),
  query: String,
  threshold: Float,
  limit: Int,
) -> Result(List(Match), String) {
  ffi_projected_exact_search(
    workspace,
    offset,
    document_rows(docs),
    query,
    threshold,
    limit,
  )
  |> result.map(matches_from_rows)
}

pub fn projection_status(
  workspace: String,
) -> Result(ProjectionStatus, String) {
  ffi_projection_status(workspace)
  |> result.try(fn(raw) {
    let #(offset, document_count, health_name, generation) = raw
    projection_health(health_name)
    |> result.map(fn(health) {
      ProjectionStatus(offset, document_count, health, generation)
    })
  })
}

fn projection_health(name: String) -> Result(projection_index.Health, String) {
  case name {
    "building" -> Ok(projection_index.Building)
    "rebuilding" -> Ok(projection_index.Rebuilding)
    "queryable" -> Ok(projection_index.Queryable)
    "degraded" -> Ok(projection_index.Degraded("managed index is degraded"))
    "failed" -> Ok(projection_index.Failed("managed index failed"))
    _ -> Error("unknown vector projection health: " <> name)
  }
}

pub fn reset_projection_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_projection(workspace)
}

fn document_rows(docs: List(Document)) -> List(#(String, String, String)) {
  docs
  |> list.map(fn(document) {
    let Document(kind, id, text) = document
    #(kind, id, text)
  })
}

fn matches_from_rows(rows: List(#(String, String, Float))) -> List(Match) {
  rows
  |> list.map(fn(row) {
    let #(kind, id, score) = row
    Match(kind, id, score)
  })
  |> list.sort(by: compare_matches)
}

/// Build an in-memory HNSW index and return ranked document matches.
///
/// `threshold` is cosine similarity because embed.embed returns normalized
/// vectors. Empty queries and non-positive limits intentionally return no
/// matches rather than making the index treat a zero vector as relevant.
pub fn search(
  docs: List(Document),
  query: String,
  threshold: Float,
  limit: Int,
) -> List(Match) {
  case string.trim(query), limit <= 0 {
    "", _ -> []
    _, True -> []
    _, False -> {
      let #(index, metadata) = build_index(docs)

      vec_index.search(index, embed.embed(query), threshold, limit)
      |> list.filter_map(fn(result) { match_for(result, metadata) })
      |> list.sort(by: compare_matches)
    }
  }
}

/// Return the exact finite-corpus oracle for Bankai's lexical vectors.
///
/// This exists for verification and benchmarks. The CLI intentionally keeps the
/// HNSW path: exact search is exhaustive rather than an interactive retrieval
/// strategy.
pub fn exact_search(
  docs: List(Document),
  query: String,
  threshold: Float,
  limit: Int,
) -> List(Match) {
  case string.trim(query), limit <= 0 {
    "", _ -> []
    _, True -> []
    _, False -> {
      let #(index, metadata) = build_index(docs)
      case vec_index.exact_search(index, embed.embed(query), threshold, limit) {
        Ok(results) ->
          results
          |> list.filter_map(fn(result) { match_for(result, metadata) })
          |> list.sort(by: compare_matches)
        Error(Nil) -> []
      }
    }
  }
}

fn build_index(
  docs: List(Document),
) -> #(vec_index.VecIndex, Dict(fact.EntityId, Document)) {
  list.fold(
    docs,
    #(
      vec_index.new_with_config(
        vec_index.deterministic_config(list.repeat(0, list.length(docs))),
      ),
      dict.new(),
    ),
    insert_document,
  )
}

fn insert_document(
  acc: #(vec_index.VecIndex, Dict(fact.EntityId, Document)),
  doc: Document,
) -> #(vec_index.VecIndex, Dict(fact.EntityId, Document)) {
  let #(index, metadata) = acc
  let entity = entity_id(doc)
  let index = vec_index.insert(index, entity, embed.embed(doc.text))
  #(index, dict.insert(metadata, entity, doc))
}

fn match_for(
  result: vec_index.SearchResult,
  metadata: Dict(fact.EntityId, Document),
) -> Result(Match, Nil) {
  case dict.get(metadata, result.entity) {
    Ok(Document(kind, id, _)) -> Ok(Match(kind, id, result.score))
    Error(Nil) -> Error(Nil)
  }
}

fn entity_id(doc: Document) -> fact.EntityId {
  let Document(kind, id, _) = doc
  let assert fact.Uid(entity) = fact.deterministic_uid(kind <> ":" <> id)
  entity
}

fn compare_matches(a: Match, b: Match) -> order.Order {
  case float.compare(b.score, a.score) {
    order.Eq -> {
      case string.compare(a.kind, b.kind) {
        order.Eq -> string.compare(a.id, b.id)
        other -> other
      }
    }
    other -> other
  }
}

pub fn backend() -> String {
  embed.backend
}
