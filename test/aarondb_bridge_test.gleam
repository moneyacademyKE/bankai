import aarondb/fact
import bankai/aarondb_bridge
import bankai/builder
import bankai/time
import bankai/types
import gleam/dict
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

/// Phase 1: status timeline over the content-addressed version history.
pub fn history_timeline_test() {
  let t0 = time.now()
  let t1 = t0 + 100
  let t2 = t0 + 200
  let v1 =
    builder.build("bk-h", "Hist", "", types.Open, option.None, 1, t0, t0, [])
  let v2 =
    builder.build(
      "bk-h",
      "Hist",
      "",
      types.InProgress,
      option.None,
      1,
      t0,
      t1,
      [],
    )
  let v3 =
    builder.build(
      "bk-h",
      "Hist",
      "",
      types.Completed,
      option.None,
      1,
      t0,
      t2,
      [],
    )
  let assert Ok(db) = aarondb_bridge.db_from_versions([v1, v2, v3])
  aarondb_bridge.history_timeline(db, "bk-h")
  |> should.equal([#(t0, "open"), #(t1, "in_progress"), #(t2, "completed")])
}

/// Phase 1: status counts + cycle times via datalog queries.
pub fn analytics_test() {
  let now = time.now()
  let open =
    builder.build("bk-a", "A", "", types.Open, option.None, 1, now, now, [])
  let done =
    builder.build(
      "bk-b",
      "B",
      "",
      types.Completed,
      option.None,
      1,
      now - 1000,
      now,
      [],
    )
  let assert Ok(db) = aarondb_bridge.db_from_tasks([open, done])
  aarondb_bridge.count_by_status(db)
  |> dict.get("completed")
  |> should.equal(Ok(1))
  aarondb_bridge.count_by_status(db) |> dict.get("open") |> should.equal(Ok(1))
  aarondb_bridge.cycle_times(db) |> should.equal([1000])
}
