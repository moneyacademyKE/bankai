//// aarondb_bridge — loads bankai's content-addressed task state into an
//// aarondb Datalog Db as EAV facts (one entity per task, one fact per field).
//// The query/analytics features (Phases 1+) run against the Db this builds.

import aarondb
import aarondb/fact
import bankai/serde
import bankai/types.{type Task}
import gleam/list
import gleam/result

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
