import aarondb/fact
import bankai/aarondb_bridge
import bankai/builder
import bankai/time
import bankai/types
import gleam/option
import gleeunit/should

/// Phase 0 acceptance: load N tasks into an aarondb Db and round-trip a query.
pub fn bridge_roundtrip_test() {
  let now = time.now()
  let t1 =
    builder.build(
      "bk-001",
      "Design API",
      "",
      types.Open,
      option.None,
      2,
      now,
      now,
      [],
    )
  let t2 =
    builder.build(
      "bk-002",
      "Ship escript",
      "",
      types.InProgress,
      option.None,
      3,
      now,
      now,
      [],
    )
  let assert Ok(db) = aarondb_bridge.db_from_tasks([t1, t2])
  aarondb_bridge.get_task_attr(db, "bk-001", "title")
  |> should.equal(Ok(fact.Str("Design API")))
  aarondb_bridge.get_task_attr(db, "bk-002", "priority")
  |> should.equal(Ok(fact.Int(3)))
}
