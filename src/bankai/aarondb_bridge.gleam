//// aarondb_bridge — loads bankai's content-addressed task state into an
//// aarondb Datalog Db and runs queries over it.
////
//// Two load modes:
////   - db_from_tasks:    one entity per task id (current-state point lookups +
////     status/cycle-time analytics).
////   - db_from_versions: one entity per content_hash version (temporal/history
////     queries — every version carries task_id + updated_at).

import aarondb
import aarondb/fact
import aarondb/index/bm25
import aarondb/q
import bankai/serde
import bankai/storage/store
import bankai/types.{type Task}
import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/result

// --- current-state loading (one entity per task id) ---

/// A fresh in-memory aarondb Db with the given bankai tasks loaded as EAV facts.
pub fn db_from_tasks(tasks: List(Task)) -> Result(aarondb.Db, String) {
  let db = aarondb.new()
  use _ <- result.try(load_tasks(db, tasks))
  Ok(db)
}

/// Transact bankai tasks into an aarondb Db. Idempotent: entities are
/// addressed by task id, so re-transacting the same task is a no-op.
pub fn load_tasks(db: aarondb.Db, tasks: List(Task)) -> Result(Nil, String) {
  let facts = list.flat_map(tasks, task_facts)
  aarondb.transact(db, facts) |> result.map(fn(_) { Nil })
}

fn task_facts(t: Task) -> List(fact.Fact) {
  let eid = fact.deterministic_uid(t.id)
  [
    #(eid, "id", fact.Str(t.id)),
    #(eid, "title", fact.Str(t.title)),
    #(eid, "status", fact.Str(serde.status_to_string(t.status))),
    #(eid, "priority", fact.Int(t.priority)),
    #(eid, "created_at", fact.Int(t.created_at)),
    #(eid, "updated_at", fact.Int(t.updated_at)),
  ]
}

/// Look up a single attribute of a task by id.
pub fn get_task_attr(
  db: aarondb.Db,
  task_id: String,
  attr: String,
) -> Result(fact.Value, Nil) {
  aarondb.get_one(db, fact.deterministic_uid(task_id), attr)
}

// --- version loading (one entity per content_hash; temporal) ---

/// Load ALL task versions as per-version EAV entities (entity = content_hash).
/// Each version carries task_id + updated_at, so temporal queries run across
/// the full version graph (store.list() is the feed).
pub fn db_from_versions(versions: List(Task)) -> Result(aarondb.Db, String) {
  let db = aarondb.new()
  use _ <- result.try(load_versions(db, versions))
  Ok(db)
}

pub fn load_versions(
  db: aarondb.Db,
  versions: List(Task),
) -> Result(Nil, String) {
  let facts = list.flat_map(versions, version_facts)
  aarondb.transact(db, facts) |> result.map(fn(_) { Nil })
}

fn version_facts(t: Task) -> List(fact.Fact) {
  let key = store.hash_key(t.content_hash)
  let eid = fact.deterministic_uid(key)
  [
    #(eid, "task_id", fact.Str(t.id)),
    #(eid, "title", fact.Str(t.title)),
    #(eid, "status", fact.Str(serde.status_to_string(t.status))),
    #(eid, "priority", fact.Int(t.priority)),
    #(eid, "created_at", fact.Int(t.created_at)),
    #(eid, "updated_at", fact.Int(t.updated_at)),
    #(eid, "content_hash", fact.Str(key)),
  ]
}

// --- queries ---

/// Status timeline for a task: List(#(updated_at, status)), ascending by time.
/// Requires a db_from_versions Db.
pub fn history_timeline(
  db: aarondb.Db,
  task_id: String,
) -> List(#(Int, String)) {
  let builder =
    q.select(["?ts", "?st"])
    |> q.where(q.v("?e"), "task_id", q.s(task_id))
    |> q.where(q.v("?e"), "updated_at", q.v("?ts"))
    |> q.where(q.v("?e"), "status", q.v("?st"))
  let res = aarondb.q(db, builder)
  res.rows
  |> list.filter_map(fn(row) {
    case dict.get(row, "?ts"), dict.get(row, "?st") {
      Ok(fact.Int(ts)), Ok(fact.Str(st)) -> Ok(#(ts, st))
      _, _ -> Error(Nil)
    }
  })
  |> list.sort(by: fn(a, b) { int.compare(a.0, b.0) })
}

/// Count tasks by status. Requires a db_from_tasks Db.
pub fn count_by_status(db: aarondb.Db) -> Dict(String, Int) {
  let builder =
    q.select(["?st"])
    |> q.where(q.v("?e"), "status", q.v("?st"))
  let res = aarondb.q(db, builder)
  list.fold(res.rows, dict.new(), count_status_row)
}

fn count_status_row(
  acc: Dict(String, Int),
  row: Dict(String, fact.Value),
) -> Dict(String, Int) {
  case dict.get(row, "?st") {
    Ok(fact.Str(st)) ->
      dict.insert(acc, st, result.unwrap(dict.get(acc, st), 0) + 1)
    _ -> acc
  }
}

/// Cycle times (updated_at - created_at) for completed/closed tasks.
/// Requires a db_from_tasks Db.
pub fn cycle_times(db: aarondb.Db) -> List(Int) {
  let builder =
    q.select(["?c", "?u", "?st"])
    |> q.where(q.v("?e"), "created_at", q.v("?c"))
    |> q.where(q.v("?e"), "updated_at", q.v("?u"))
    |> q.where(q.v("?e"), "status", q.v("?st"))
  let res = aarondb.q(db, builder)
  list.filter_map(res.rows, fn(row) {
    case dict.get(row, "?st"), dict.get(row, "?u"), dict.get(row, "?c") {
      Ok(fact.Str(st)), Ok(fact.Int(u)), Ok(fact.Int(c)) ->
        case st == "completed" || st == "closed" {
          True -> Ok(u - c)
          False -> Error(Nil)
        }
      _, _, _ -> Error(Nil)
    }
  })
}

// --- full-text search (BM25) ---

fn entity_id(key: String) -> fact.EntityId {
  let assert fact.Uid(eid) = fact.deterministic_uid(key)
  eid
}

/// Full-text search over documents via aarondb's BM25 index. `docs` are
/// (kind, id, text) triples; returns (kind, id, score) ranked desc, score > 0.
pub fn search(
  docs: List(#(String, String, String)),
  query: String,
) -> List(#(String, String, Float)) {
  let idx =
    list.fold(docs, bm25.empty("text"), fn(i, d) {
      let #(_, id, text) = d
      bm25.add(i, entity_id(id), text)
    })
  docs
  |> list.filter_map(fn(d) {
    let #(kind, id, _) = d
    let sc = bm25.score(idx, entity_id(id), query, 1.2, 0.75)
    case sc >. 0.0 {
      True -> Ok(#(kind, id, sc))
      False -> Error(Nil)
    }
  })
  |> list.sort(by: fn(a, b) {
    let #(_, _, sa) = a
    let #(_, _, sb) = b
    float.compare(sb, sa)
  })
}
