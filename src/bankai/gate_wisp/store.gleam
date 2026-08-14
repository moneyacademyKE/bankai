import gleam/list
import gleam/option.{type Option}
import gleam/result

pub type GateAudit {
  GateAudit(
    sequence: Int,
    gate_id: String,
    action: String,
    actor: String,
    reason: String,
    resolved_hash: String,
    at: Int,
  )
}

pub type StoredFact {
  StoredFact(
    signature: String,
    issuer: String,
    state: String,
    observed_at: Int,
    expires_at: Int,
    wire: String,
  )
}

pub type WispArchive {
  WispArchive(
    sequence: Int,
    wisp_id: String,
    action: String,
    actor: String,
    reason: String,
    task_hash: String,
    task_json: String,
    at: Int,
  )
}

@external(erlang, "bankai_gate_wisps_ffi", "init")
fn ffi_init(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_gate_wisps_ffi", "reset_workspace")
fn ffi_reset_workspace(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_gate_wisps_ffi", "resolve_gate")
fn ffi_resolve_gate(
  workspace: String,
  gate_id: String,
  expected_hash: String,
  new_hash: String,
  new_json: String,
  action: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String)

@external(erlang, "bankai_gate_wisps_ffi", "gate_audits")
fn ffi_gate_audits(
  workspace: String,
  gate_id: String,
) -> Result(List(#(Int, String, String, String, String, String, Int)), String)

@external(erlang, "bankai_gate_wisps_ffi", "apply_verified_fact")
fn ffi_apply_verified_fact(
  workspace: String,
  gate_id: String,
  expected_hash: String,
  new_head: #(String, String),
  fact: #(String, String, String, Int, Int),
  wire: String,
  reason: String,
  at: Int,
) -> Result(#(Bool, Int), String)

@external(erlang, "bankai_gate_wisps_ffi", "valid_facts")
fn ffi_valid_facts(
  workspace: String,
  gate_id: String,
  now: Int,
) -> Result(List(#(String, String, String, Int, Int, String)), String)

@external(erlang, "bankai_gate_wisps_ffi", "create_wisp")
fn ffi_create_wisp(
  workspace: String,
  id: String,
  hash: String,
  task_json: String,
  expiry: Option(Int),
) -> Result(String, String)

@external(erlang, "bankai_gate_wisps_ffi", "get_wisp_metadata")
fn ffi_get_wisp_metadata(
  workspace: String,
  wisp_id: String,
) -> Result(Option(Int), String)

@external(erlang, "bankai_gate_wisps_ffi", "transition_wisp")
fn ffi_transition_wisp(
  workspace: String,
  id: String,
  expected_hash: String,
  new_hash: String,
  new_json: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String)

@external(erlang, "bankai_gate_wisps_ffi", "burn_wisps")
fn ffi_burn_wisps(
  workspace: String,
  rows: List(#(String, String, Int)),
  action: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String)

@external(erlang, "bankai_gate_wisps_ffi", "wisp_archives")
fn ffi_wisp_archives(
  workspace: String,
  wisp_id: String,
) -> Result(
  List(#(Int, String, String, String, String, String, String, Int)),
  String,
)

pub fn init(workspace: String) -> Result(Nil, String) {
  ffi_init(workspace)
}

pub fn reset_workspace_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_workspace(workspace)
}

pub fn resolve_gate(
  workspace: String,
  gate_id: String,
  expected_hash: String,
  new_hash: String,
  new_json: String,
  action: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String) {
  ffi_resolve_gate(
    workspace,
    gate_id,
    expected_hash,
    new_hash,
    new_json,
    action,
    actor,
    reason,
    at,
  )
}

pub fn gate_audits(
  workspace: String,
  gate_id: String,
) -> Result(List(GateAudit), String) {
  ffi_gate_audits(workspace, gate_id)
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      let #(sequence, id, action, actor, reason, resolved_hash, at) = row
      GateAudit(sequence, id, action, actor, reason, resolved_hash, at)
    })
  })
}

pub fn apply_verified_fact(
  workspace: String,
  gate_id: String,
  expected_hash: String,
  new_hash: String,
  new_json: String,
  signature: String,
  issuer: String,
  observed_at: Int,
  expires_at: Int,
  wire: String,
  reason: String,
  at: Int,
) -> Result(#(Bool, Int), String) {
  ffi_apply_verified_fact(
    workspace,
    gate_id,
    expected_hash,
    #(new_hash, new_json),
    #(signature, issuer, "satisfied", observed_at, expires_at),
    wire,
    reason,
    at,
  )
}

pub fn valid_facts(
  workspace: String,
  gate_id: String,
  now: Int,
) -> Result(List(StoredFact), String) {
  ffi_valid_facts(workspace, gate_id, now)
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      let #(signature, issuer, state, observed_at, expires_at, wire) = row
      StoredFact(signature, issuer, state, observed_at, expires_at, wire)
    })
  })
}

pub fn create_wisp(
  workspace: String,
  id: String,
  hash: String,
  task_json: String,
  expiry: Option(Int),
) -> Result(String, String) {
  ffi_create_wisp(workspace, id, hash, task_json, expiry)
}

pub fn wisp_expiry(
  workspace: String,
  wisp_id: String,
) -> Result(Option(Int), String) {
  ffi_get_wisp_metadata(workspace, wisp_id)
}

pub fn promote_wisp(
  workspace: String,
  id: String,
  expected_hash: String,
  new_hash: String,
  new_json: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String) {
  ffi_transition_wisp(
    workspace,
    id,
    expected_hash,
    new_hash,
    new_json,
    actor,
    reason,
    at,
  )
}

pub fn burn_wisps(
  workspace: String,
  rows: List(#(String, String, Int)),
  action: String,
  actor: String,
  reason: String,
  at: Int,
) -> Result(Int, String) {
  ffi_burn_wisps(workspace, rows, action, actor, reason, at)
}

pub fn wisp_archives(
  workspace: String,
  wisp_id: String,
) -> Result(List(WispArchive), String) {
  ffi_wisp_archives(workspace, wisp_id)
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      let #(sequence, id, action, actor, reason, task_hash, task_json, at) = row
      WispArchive(sequence, id, action, actor, reason, task_hash, task_json, at)
    })
  })
}
