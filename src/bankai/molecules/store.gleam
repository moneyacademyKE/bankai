import bankai/molecules/types
import gleam/json
import gleam/list
import gleam/option.{type Option}
import gleam/result

pub type TemplateSummary {
  TemplateSummary(hash: String, schema: Int, name: String)
}

pub type Instance {
  Instance(
    template_hash: String,
    idempotency_key: String,
    fingerprint: String,
    instance_id: String,
    bindings_json: String,
    node_tasks: List(#(String, String)),
    created_at: Int,
    replayed: Bool,
  )
}

pub type InstanceData {
  InstanceData(
    template_hash: String,
    idempotency_key: String,
    fingerprint: String,
    bindings_json: String,
    node_tasks: List(#(String, String)),
    created_at: Int,
  )
}

@external(erlang, "bankai_molecules_ffi", "init")
fn ffi_init(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_molecules_ffi", "reset_workspace")
fn ffi_reset_workspace(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_molecules_ffi", "register")
fn ffi_register(
  workspace: String,
  hash: String,
  schema: Int,
  name: String,
  source: String,
) -> Result(Nil, String)

@external(erlang, "bankai_molecules_ffi", "get")
fn ffi_get(
  workspace: String,
  hash: String,
) -> Result(#(Int, String, String), String)

@external(erlang, "bankai_molecules_ffi", "list")
fn ffi_list(workspace: String) -> Result(List(#(String, Int, String)), String)

@external(erlang, "bankai_molecules_ffi", "instance_by_key")
fn ffi_instance_by_key(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
) -> Result(
  Option(#(String, String, String, List(#(String, String)), Int)),
  String,
)

@external(erlang, "bankai_molecules_ffi", "instantiate")
fn ffi_instantiate(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
  fingerprint: String,
  instance_id: String,
  bindings_json: String,
  task_rows: List(#(String, String, String, String)),
  created_at: Int,
  reserved: String,
) -> Result(#(String, String, List(#(String, String)), Int, Bool), String)

@external(erlang, "bankai_molecules_ffi", "instance")
fn ffi_instance(
  workspace: String,
  instance_id: String,
) -> Result(
  #(String, String, String, String, List(#(String, String)), Int),
  String,
)

@external(erlang, "bankai_molecules_ffi", "provenance")
fn ffi_provenance(
  workspace: String,
  task_id: String,
) -> Result(#(String, String, String), String)

pub fn init(workspace: String) -> Result(Nil, String) {
  ffi_init(workspace)
}

pub fn reset_workspace_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_workspace(workspace)
}

pub fn register(
  workspace: String,
  hash: String,
  template: types.Template,
  source: String,
) -> Result(Nil, String) {
  let types.Template(schema, name, _, _, _) = template
  ffi_register(workspace, hash, schema, name, source)
}

pub fn get(
  workspace: String,
  hash: String,
) -> Result(#(types.Template, String), String) {
  ffi_get(workspace, hash)
  |> result.try(fn(row) {
    let #(_, _, source) = row
    types.decode_template(source)
    |> result.map(fn(template) { #(template, source) })
  })
}

pub fn list(workspace: String) -> Result(List(TemplateSummary), String) {
  ffi_list(workspace)
  |> result.map(fn(rows) {
    list.map(rows, fn(row) {
      let #(hash, schema, name) = row
      TemplateSummary(hash, schema, name)
    })
  })
}

pub fn instance_by_key(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
) -> Result(Option(Instance), String) {
  ffi_instance_by_key(workspace, template_hash, idempotency_key)
  |> result.map(fn(saved) {
    case saved {
      option.Some(#(fingerprint, instance_id, bindings_json, node_tasks, at)) ->
        option.Some(Instance(
          template_hash,
          idempotency_key,
          fingerprint,
          instance_id,
          bindings_json,
          node_tasks,
          at,
          True,
        ))
      option.None -> option.None
    }
  })
}

pub fn instantiate(
  workspace: String,
  template_hash: String,
  idempotency_key: String,
  fingerprint: String,
  instance_id: String,
  bindings_json: String,
  task_rows: List(#(String, String, String, String)),
  created_at: Int,
) -> Result(Instance, String) {
  ffi_instantiate(
    workspace,
    template_hash,
    idempotency_key,
    fingerprint,
    instance_id,
    bindings_json,
    task_rows,
    created_at,
    "",
  )
  |> result.map(fn(saved) {
    let #(saved_id, saved_bindings, node_tasks, saved_at, replayed) = saved
    Instance(
      template_hash,
      idempotency_key,
      fingerprint,
      saved_id,
      saved_bindings,
      node_tasks,
      saved_at,
      replayed,
    )
  })
}

pub fn instance(
  workspace: String,
  instance_id: String,
) -> Result(InstanceData, String) {
  ffi_instance(workspace, instance_id)
  |> result.map(fn(saved) {
    let #(template_hash, key, fingerprint, bindings, nodes, created_at) = saved
    InstanceData(template_hash, key, fingerprint, bindings, nodes, created_at)
  })
}

pub fn provenance(
  workspace: String,
  task_id: String,
) -> Result(#(String, String, String), String) {
  ffi_provenance(workspace, task_id)
}

pub fn summary_json(summary: TemplateSummary) -> json.Json {
  json.object([
    #("hash", json.string(summary.hash)),
    #("schema", json.int(summary.schema)),
    #("name", json.string(summary.name)),
  ])
}
