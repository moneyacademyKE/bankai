import bankai/rules/registry
import gleam/json
import gleam/list
import gleam/result

pub type Artifact {
  Artifact(hash: String, name: String, approved: Bool)
}

pub type Audit {
  Audit(
    sequence: Int,
    hash: String,
    caller: String,
    input_hash: String,
    task_id: String,
    task_hash: String,
    duration_ns: Int,
    outcome: String,
    result: String,
  )
}

@external(erlang, "bankai_rules_ffi", "init")
fn ffi_init(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_rules_ffi", "reset_workspace")
fn ffi_reset_workspace(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_rules_ffi", "register")
fn ffi_register(
  workspace: String,
  hash: String,
  name: String,
  source: String,
) -> Result(Nil, String)

@external(erlang, "bankai_rules_ffi", "get")
fn ffi_get(workspace: String, hash: String) -> Result(#(String, String), String)

@external(erlang, "bankai_rules_ffi", "list")
fn ffi_list(workspace: String) -> Result(List(#(String, String, Bool)), String)

@external(erlang, "bankai_rules_ffi", "set_approval")
fn ffi_set_approval(
  workspace: String,
  hash: String,
  approved: Bool,
) -> Result(Nil, String)

@external(erlang, "bankai_rules_ffi", "is_approved")
fn ffi_is_approved(workspace: String, hash: String) -> Result(Bool, String)

@external(erlang, "bankai_rules_ffi", "append_audit")
fn ffi_append_audit(
  workspace: String,
  hash: String,
  caller: String,
  input_hash: String,
  task_id: String,
  task_hash: String,
  duration_ns: Int,
  outcome: String,
  result_text: String,
  reserved: String,
) -> Result(Int, String)

@external(erlang, "bankai_rules_ffi", "list_audit")
fn ffi_list_audit(
  workspace: String,
  hash: String,
) -> Result(
  List(#(Int, String, String, String, String, String, Int, String, String)),
  String,
)

pub fn init(workspace: String) -> Result(Nil, String) {
  ffi_init(workspace)
}

/// Test-only cleanup for one workspace. It never drops schemas or other rows.
pub fn reset_workspace_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_workspace(workspace)
}

pub fn source_hash(source: String) -> String {
  registry.source_hash_text(source)
}

pub fn register(
  workspace: String,
  name: String,
  source: String,
) -> Result(String, String) {
  let hash = source_hash(source)
  ffi_register(workspace, hash, name, source)
  |> result.map(fn(_) { hash })
}

pub fn get(
  workspace: String,
  hash: String,
) -> Result(#(String, String), String) {
  ffi_get(workspace, hash)
}

pub fn list(workspace: String) -> Result(List(Artifact), String) {
  ffi_list(workspace)
  |> result.map(fn(rows) {
    rows
    |> list.map(fn(row) {
      let #(hash, name, approved) = row
      Artifact(hash:, name:, approved:)
    })
  })
}

pub fn approve(workspace: String, hash: String) -> Result(Nil, String) {
  ffi_set_approval(workspace, hash, True)
}

pub fn revoke(workspace: String, hash: String) -> Result(Nil, String) {
  ffi_set_approval(workspace, hash, False)
}

pub fn is_approved(workspace: String, hash: String) -> Result(Bool, String) {
  ffi_is_approved(workspace, hash)
}

pub fn append_audit(
  workspace: String,
  hash: String,
  caller: String,
  input_hash: String,
  task_id: String,
  task_hash: String,
  duration_ns: Int,
  outcome: String,
  result_text: String,
) -> Result(Int, String) {
  ffi_append_audit(
    workspace,
    hash,
    caller,
    input_hash,
    task_id,
    task_hash,
    duration_ns,
    outcome,
    result_text,
    "",
  )
}

/// Empty hash means the complete local audit stream.
pub fn audits(workspace: String, hash: String) -> Result(List(Audit), String) {
  ffi_list_audit(workspace, hash)
  |> result.map(fn(rows) {
    rows
    |> list.map(fn(row) {
      let #(
        sequence,
        rule_hash,
        caller,
        input_hash,
        task_id,
        task_hash,
        duration_ns,
        outcome,
        result_text,
      ) = row
      Audit(
        sequence:,
        hash: rule_hash,
        caller:,
        input_hash:,
        task_id:,
        task_hash:,
        duration_ns:,
        outcome:,
        result: result_text,
      )
    })
  })
}

pub fn artifact_to_json(artifact: Artifact) -> json.Json {
  json.object([
    #("hash", json.string(artifact.hash)),
    #("name", json.string(artifact.name)),
    #("approved", json.bool(artifact.approved)),
  ])
}

pub fn audit_to_json(audit: Audit) -> json.Json {
  json.object([
    #("sequence", json.int(audit.sequence)),
    #("hash", json.string(audit.hash)),
    #("caller", json.string(audit.caller)),
    #("input_hash", json.string(audit.input_hash)),
    #("task_id", nullable_text(audit.task_id)),
    #("task_hash", nullable_text(audit.task_hash)),
    #("duration_ns", json.int(audit.duration_ns)),
    #("outcome", json.string(audit.outcome)),
    #("result", json.string(audit.result)),
  ])
}

fn nullable_text(text: String) -> json.Json {
  case text == "" {
    True -> json.null()
    False -> json.string(text)
  }
}
