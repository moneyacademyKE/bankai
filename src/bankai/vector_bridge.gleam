//// Vector retrieval over aarondb's HNSW index.
////
//// Mnesia is Bankai's source of truth. This module builds a short-lived index
//// from Bankai documents for one command, keeping aarondb behind a Bankai-shaped
//// result type and the embedding backend behind bankai/embed.

import aarondb/fact
import aarondb/vec_index
import bankai/embed
import gleam/dict.{type Dict}
import gleam/float
import gleam/list
import gleam/order
import gleam/string

pub type Document {
  Document(kind: String, id: String, text: String)
}

pub type Match {
  Match(kind: String, id: String, score: Float)
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
      let #(index, metadata) =
        list.fold(docs, #(vec_index.new(), dict.new()), insert_document)

      vec_index.search(index, embed.embed(query), threshold, limit)
      |> list.filter_map(fn(result) { match_for(result, metadata) })
      |> list.sort(by: compare_matches)
    }
  }
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
