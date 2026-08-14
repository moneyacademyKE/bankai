//// Complete local gate lifecycle service. External systems are represented
//// only by already-signed fact data; this module performs no provider I/O.

import bankai/builder
import bankai/gate_wisp/store as lifecycle_store
import bankai/gates/facts
import bankai/gates/policy
import bankai/mnesia_store
import bankai/serde
import bankai/storage/store
import bankai/time
import bankai/types.{type Task, Gate, Task}
import gleam/json
import gleam/list as gleam_list
import gleam/result
import gleam/string
import gleamunison/identity

pub fn readiness_tasks(
  workspace: String,
  tasks: List(Task),
  now: Int,
) -> Result(List(Task), String) {
  tasks
  |> gleam_list.try_map(fn(task) {
    case task.kind, task.gate_satisfied {
      Gate, False -> {
        use stored <- result.try(lifecycle_store.valid_facts(
          workspace,
          task.id,
          now,
        ))
        use active <- result.try(active_facts(workspace, stored))
        Ok(case gleam_list.is_empty(active) {
          True -> task
          False -> Task(..task, gate_satisfied: True)
        })
      }
      _, _ -> Ok(task)
    }
  })
}

pub fn list(
  workspace: String,
  args: List(String),
) -> Result(json.Json, String) {
  let wanted = option_value(args, "--state", "all")
  use _ <- result.try(case wanted {
    "all" | "open" | "pending" -> Ok(Nil)
    _ -> Error("gate state must be all, open, or pending")
  })
  use tasks <- result.try(current_tasks(workspace))
  let now = time.now()
  tasks
  |> gates()
  |> gleam_list.try_map(fn(gate) { gate_summary(workspace, gate, tasks, now) })
  |> result.map(fn(rows) {
    rows
    |> gleam_list.filter(fn(row) {
      wanted == "all"
      || string.contains(
        json.to_string(row),
        "\"open\":" <> bool_text(wanted == "open"),
      )
    })
    |> json.array(of: fn(row) { row })
  })
}

pub fn show(workspace: String, id: String) -> Result(json.Json, String) {
  use gate <- result.try(get_gate(workspace, id))
  use tasks <- result.try(current_tasks(workspace))
  use evaluation <- result.try(evaluate(workspace, gate, tasks, time.now()))
  use audits <- result.try(lifecycle_store.gate_audits(workspace, id))
  Ok(
    json.object([
      #("evaluation", evaluation),
      #("escalation", escalation(gate)),
      #(
        "audit",
        json.array(audits, of: fn(audit) {
          json.object([
            #("sequence", json.int(audit.sequence)),
            #("action", json.string(audit.action)),
            #("actor", json.string(audit.actor)),
            #("reason", json.string(audit.reason)),
            #("resolved_hash", json.string(audit.resolved_hash)),
            #("at", json.int(audit.at)),
          ])
        }),
      ),
    ]),
  )
}

pub fn check(workspace: String, id: String) -> Result(json.Json, String) {
  use gate <- result.try(get_gate(workspace, id))
  use tasks <- result.try(current_tasks(workspace))
  evaluate(workspace, gate, tasks, time.now())
}

pub fn resolve(
  workspace: String,
  id: String,
  args: List(String),
) -> Result(json.Json, String) {
  use gate <- result.try(get_gate(workspace, id))
  use tasks <- result.try(current_tasks(workspace))
  let now = time.now()
  use before <- result.try(evaluate(workspace, gate, tasks, now))
  let reason = option_value(args, "--reason", "manual resolution")
  let actor = option_value(args, "--actor", "local")
  let dry_run = has_flag(args, "--dry-run")
  let already_open = gate.gate_satisfied
  let would_change = !already_open
  let preview =
    json.object([
      #("dry_run", json.bool(dry_run)),
      #("would_change", json.bool(would_change)),
      #(
        "action",
        json.string(case already_open {
          True -> "no_op"
          False -> "resolve"
        }),
      ),
      #("reason", json.string(reason)),
      #("actor", json.string(actor)),
      #("before", before),
      #("escalation", escalation(gate)),
    ])
  case dry_run, already_open {
    True, _ -> Ok(preview)
    False, True -> Ok(preview)
    False, False -> {
      let updated =
        builder.update(gate, fn(current) {
          Task(..current, gate_satisfied: True, updated_at: now)
        })
      use sequence <- result.try(lifecycle_store.resolve_gate(
        workspace,
        id,
        hash(gate),
        hash(updated),
        serde.task_to_json_string(updated),
        "manual",
        actor,
        reason,
        now,
      ))
      use refreshed <- result.try(current_tasks(workspace))
      use after <- result.try(evaluate(workspace, updated, refreshed, now))
      Ok(
        json.object([
          #("resolved", json.bool(True)),
          #("audit_sequence", json.int(sequence)),
          #("reason", json.string(reason)),
          #("actor", json.string(actor)),
          #("after", after),
        ]),
      )
    }
  }
}

/// Verify before crossing the transactional persistence boundary. The verified
/// fields, signature replay marker, gate head, audit, and change event then
/// commit together.
pub fn ingest_fact(
  workspace: String,
  id: String,
  issuer: String,
  wire_json: String,
) -> Result(json.Json, String) {
  use gate <- result.try(get_gate(workspace, id))
  use wire <- result.try(facts.decode(wire_json))
  let now = time.now()
  use verified <- result.try(facts.verify(workspace, wire, id, issuer, now))
  let facts.Fact(_, _, observed_at, expires_at, author, signature) = verified
  case gate.gate_satisfied {
    True ->
      Ok(
        json.object([
          #("verified", json.bool(True)),
          #("persisted", json.bool(False)),
          #("replay", json.bool(False)),
          #("gate_id", json.string(id)),
          #("issuer", json.string(author)),
          #("reason", json.string("gate already manually resolved")),
        ]),
      )
    False ->
      persist_verified_fact(
        workspace,
        gate,
        wire_json,
        observed_at,
        expires_at,
        author,
        signature,
        now,
      )
  }
}

fn persist_verified_fact(
  workspace: String,
  gate: Task,
  wire_json: String,
  observed_at: Int,
  expires_at: Int,
  author: String,
  signature: String,
  now: Int,
) -> Result(json.Json, String) {
  let updated = gate
  use stored <- result.try(lifecycle_store.apply_verified_fact(
    workspace,
    gate.id,
    hash(gate),
    hash(updated),
    serde.task_to_json_string(updated),
    signature,
    author,
    observed_at,
    expires_at,
    wire_json,
    "verified signed external fact",
    now,
  ))
  let #(created, sequence) = stored
  Ok(
    json.object([
      #("verified", json.bool(True)),
      #("persisted", json.bool(created)),
      #("replay", json.bool(!created)),
      #("gate_id", json.string(gate.id)),
      #("issuer", json.string(author)),
      #("expires_at", json.int(expires_at)),
      #("audit_sequence", json.int(sequence)),
    ]),
  )
}

fn gate_summary(
  workspace: String,
  gate: Task,
  tasks: List(Task),
  now: Int,
) -> Result(json.Json, String) {
  use stored_facts <- result.try(lifecycle_store.valid_facts(
    workspace,
    gate.id,
    now,
  ))
  use active_facts <- result.try(active_facts(workspace, stored_facts))
  let state = policy.state(gate, !gleam_list.is_empty(active_facts), now)
  Ok(
    json.object([
      #("gate_id", json.string(gate.id)),
      #("title", json.string(gate.title)),
      #("open", json.bool(policy.is_open(state))),
      #("reasons", json.array(policy.reasons(state), of: json.string)),
      #(
        "waiter_count",
        json.int(gleam_list.length(policy.waiters(gate.id, tasks))),
      ),
      #("escalation", escalation(gate)),
    ]),
  )
}

fn evaluate(
  workspace: String,
  gate: Task,
  tasks: List(Task),
  now: Int,
) -> Result(json.Json, String) {
  use stored_facts <- result.try(lifecycle_store.valid_facts(
    workspace,
    gate.id,
    now,
  ))
  use active <- result.try(active_facts(workspace, stored_facts))
  Ok(policy.evaluate(gate, tasks, !gleam_list.is_empty(active), now))
}

fn active_facts(
  workspace: String,
  stored_facts: List(lifecycle_store.StoredFact),
) -> Result(List(lifecycle_store.StoredFact), String) {
  stored_facts
  |> gleam_list.try_map(fn(stored: lifecycle_store.StoredFact) {
    facts.issuer_status(workspace, stored.issuer)
    |> result.map(fn(status) {
      let #(trusted, revoked) = status
      #(stored, trusted && !revoked)
    })
  })
  |> result.map(fn(statuses) {
    statuses
    |> gleam_list.filter(fn(pair) { pair.1 })
    |> gleam_list.map(fn(pair) { pair.0 })
  })
}

fn escalation(gate: Task) -> json.Json {
  let destinations =
    gate.labels
    |> gleam_list.filter_map(fn(label) {
      case string.starts_with(label, "escalate:") {
        True -> Ok(string.drop_start(label, 9))
        False -> Error(Nil)
      }
    })
    |> gleam_list.sort(by: string.compare)
  json.object([
    #("local_only", json.bool(True)),
    #("requested", json.bool(!gleam_list.is_empty(destinations))),
    #("destinations", json.array(destinations, of: json.string)),
    #("network_attempted", json.bool(False)),
  ])
}

fn get_gate(workspace: String, id: String) -> Result(Task, String) {
  mnesia_store.get_current(workspace, id)
  |> result.try(fn(task) {
    case task.kind {
      Gate -> Ok(task)
      _ -> Error("task is not a gate: " <> id)
    }
  })
}

fn current_tasks(workspace: String) -> Result(List(Task), String) {
  mnesia_store.current_store(workspace)
  |> result.map(store.current_tasks)
}

fn gates(tasks: List(Task)) -> List(Task) {
  tasks
  |> gleam_list.filter(fn(task) { task.kind == Gate })
  |> gleam_list.sort(by: fn(a, b) { string.compare(a.id, b.id) })
}

fn option_value(args: List(String), name: String, default: String) -> String {
  case args {
    [flag, value, ..] if flag == name -> value
    [_, ..rest] -> option_value(rest, name, default)
    [] -> default
  }
}

fn has_flag(args: List(String), wanted: String) -> Bool {
  gleam_list.any(args, fn(value) { value == wanted })
}

fn hash(task: Task) -> String {
  identity.hash_to_debug_string(task.content_hash)
}

fn bool_text(value: Bool) -> String {
  case value {
    True -> "true"
    False -> "false"
  }
}
