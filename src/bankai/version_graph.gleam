//// Causal ancestry over content-addressed task versions.
////
//// A version hash identifies content, never a position in history: two rigs
//// that both advance from hash H produce two different children of H. Only the
//// parent links distinguish "the peer is ahead of me" from "we both moved".
//// This module is the pure classifier over those links — it decides nothing
//// about storage, so the same rules serve the import path, the CLI and tests.
////
//// Links travel with a replica snapshot (child hash -> parent hashes) because
//// ancestry created on the sender is not observable on the receiver.

import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/set

/// A child hash and the hashes it was produced from.
pub type Ancestry =
  List(#(String, List(String)))

/// How a remote head relates to the local head of the same task.
pub type SyncClass {
  /// Same bytes on both sides: nothing to move.
  Identical
  /// The local head is an ancestor of the remote head: accept the remote.
  FastForward
  /// The remote head is an ancestor of the local head: keep the local.
  Stale
  /// Both sides advanced from a common ancestor: a real conflict.
  Divergent
}

pub type Graph {
  Graph(parents: Dict(String, List(String)))
}

pub fn empty() -> Graph {
  Graph(parents: dict.new())
}

/// Build a graph from ancestry rows. Duplicate child rows union their parents,
/// so two peers that each know one parent of the same child keep both.
pub fn graph(ancestry: Ancestry) -> Graph {
  Graph(parents: list.fold(ancestry, dict.new(), add_link))
}

fn add_link(
  acc: Dict(String, List(String)),
  link: #(String, List(String)),
) -> Dict(String, List(String)) {
  let #(child, parents) = link
  let existing = dict.get(acc, child) |> result.unwrap([])
  dict.insert(
    acc,
    child,
    list.append(
      existing,
      list.filter(parents, fn(p) { !list.contains(existing, p) }),
    ),
  )
}

/// Every ancestor of `hash`, nearest first. Cycle-safe: a malformed ancestry
/// row can never loop, it just stops contributing.
pub fn ancestors(graph: Graph, hash: String) -> List(String) {
  walk(graph, [hash], set.new())
  |> list.filter(fn(h) { h != hash })
}

fn walk(
  graph: Graph,
  frontier: List(String),
  seen: set.Set(String),
) -> List(String) {
  case frontier {
    [] -> set.to_list(seen)
    [hash, ..rest] ->
      case set.contains(seen, hash) {
        True -> walk(graph, rest, seen)
        False -> {
          let seen = set.insert(seen, hash)
          let parents = dict.get(graph.parents, hash) |> result.unwrap([])
          walk(graph, list.append(rest, parents), seen)
        }
      }
  }
}

/// Classify a remote head against the local head of the same task.
pub fn classify(graph: Graph, local: String, remote: String) -> SyncClass {
  case local == remote {
    True -> Identical
    False ->
      case list.contains(ancestors(graph, remote), local) {
        True -> FastForward
        False ->
          case list.contains(ancestors(graph, local), remote) {
            True -> Stale
            False -> Divergent
          }
      }
  }
}

/// Stable wording for CLI and error surfaces.
pub fn describe(class: SyncClass) -> String {
  case class {
    Identical -> "identical"
    FastForward -> "fast-forward"
    Stale -> "stale"
    Divergent -> "divergent"
  }
}
