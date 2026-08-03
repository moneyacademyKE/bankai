//// Validation gates for actor transitions. Pure — no side effects.

import bankai/graph

/// Gate an AddRelation: reject if adding (task_id -> target_id) would create a
/// dependency cycle in the current graph context `all_edges`.
pub fn relation_ok(
  task_id: String,
  target_id: String,
  all_edges: List(#(String, String)),
) -> Result(Nil, String) {
  case graph.would_cycle(all_edges, #(task_id, target_id)) {
    True ->
      Error("relation would create a cycle: " <> task_id <> " -> " <> target_id)
    False -> Ok(Nil)
  }
}
