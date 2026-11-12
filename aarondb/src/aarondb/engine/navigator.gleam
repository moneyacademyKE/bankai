import aarondb/shared/ast.{type BodyClause}
import aarondb/shared/optimizer
import gleam/option.{None}

/// Legacy bridge to centralized optimizer.
/// Rich Hickey alignment: "Namespaces are good, but logic should be where it belongs."
pub fn plan(clauses: List(BodyClause)) -> List(BodyClause) {
  optimizer.optimize(ast.Query(
    find: [],
    where: clauses,
    order_by: None,
    limit: None,
    offset: None,
  )).where
}

pub fn explain(clauses: List(BodyClause)) -> String {
  optimizer.explain(clauses)
}
