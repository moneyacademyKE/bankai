import bankai/daemon_store
import bankai/mcp
import bankai/mnesia_store
import bankai/molecules/service
import bankai/molecules/store as molecule_store
import bankai/service_auth
import bankai/socket
import bankai/storage/store as task_store
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace_registry = "/tmp/bankai_molecule_registry_test"

const workspace_instance = "/tmp/bankai_molecule_instance_test"

const workspace_progress = "/tmp/bankai_molecule_progress_test"

const workspace_protocol = "/tmp/bankai_molecule_protocol_test"

const valid_template = "{\"schema\":1,\"name\":\"release\",\"variables\":[{\"name\":\"project\",\"required\":true}],\"nodes\":[{\"name\":\"build\",\"title\":\"Build {{project}}\",\"kind\":\"task\",\"priority\":2,\"labels\":[\"build\"]},{\"name\":\"test\",\"title\":\"Test {{project}}\",\"kind\":\"task\",\"priority\":1,\"labels\":[]}],\"edges\":[{\"from\":\"test\",\"to\":\"build\",\"relation\":\"blocks\"}]}"

const invalid_template = "{\"schema\":1,\"name\":\"bad\",\"variables\":[],\"nodes\":[{\"name\":\"only\",\"title\":\"Unknown {{value}}\",\"kind\":\"task\",\"priority\":1,\"labels\":[]}],\"edges\":[]}"

fn reset(workspace: String) -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  let _ = simplifile.write("", to: workspace <> "/memories.jsonl")
  let _ = simplifile.write("", to: workspace <> "/archive.jsonl")
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = molecule_store.init(workspace)
  let _ = molecule_store.reset_workspace_for_test(workspace)
  service_auth.reset_for_test(workspace)
}

fn field(value: json.Json, name: String) -> String {
  json.to_string(value)
  |> string.split("\"" <> name <> "\":\"")
  |> list.drop(1)
  |> list.first
  |> fn(found) {
    case found {
      Ok(tail) ->
        tail
        |> string.split("\"")
        |> list.first
        |> fn(part) {
          case part {
            Ok(text) -> text
            Error(_) -> ""
          }
        }
      Error(_) -> ""
    }
  }
}

fn task_id_for_node(value: json.Json, node: String) -> String {
  json.to_string(value)
  |> string.split("\"node\":\"" <> node <> "\",\"task_id\":\"")
  |> list.drop(1)
  |> list.first
  |> fn(found) {
    case found {
      Ok(tail) -> tail |> string.split("\"") |> list.first |> result_or_empty
      Error(_) -> ""
    }
  }
}

fn result_or_empty(value: Result(String, Nil)) -> String {
  case value {
    Ok(text) -> text
    Error(_) -> ""
  }
}

pub fn templates_validate_shape_and_graph_before_registration_test() {
  let workspace = workspace_registry
  reset(workspace)
  let invalid_templates = [
    invalid_template,
    "{\"schema\":1,\"name\":\"duplicate\",\"nodes\":[{\"name\":\"same\",\"title\":\"One\"},{\"name\":\"same\",\"title\":\"Two\"}]}",
    "{\"schema\":1,\"name\":\"endpoint\",\"nodes\":[{\"name\":\"one\",\"title\":\"One\"}],\"edges\":[{\"from\":\"one\",\"to\":\"missing\",\"relation\":\"blocks\"}]}",
    "{\"schema\":1,\"name\":\"parent\",\"nodes\":[{\"name\":\"one\",\"title\":\"One\",\"parent\":\"missing\"}]}",
    "{\"schema\":1,\"name\":\"cycle\",\"nodes\":[{\"name\":\"one\",\"title\":\"One\"},{\"name\":\"two\",\"title\":\"Two\"}],\"edges\":[{\"from\":\"one\",\"to\":\"two\",\"relation\":\"blocks\"},{\"from\":\"two\",\"to\":\"one\",\"relation\":\"blocks\"}]}",
  ]
  invalid_templates
  |> list.each(fn(source) {
    service.register(workspace, source) |> should.be_error
  })
  should.be_ok(service.list(workspace))
  |> json.to_string
  |> should.equal("[]")
}

pub fn templates_are_content_addressed_immutable_data_test() {
  let workspace = workspace_registry
  reset(workspace)
  let first = should.be_ok(service.register(workspace, valid_template))
  let reordered =
    "{\"name\":\"release\",\"schema\":1,\"edges\":[{\"relation\":\"blocks\",\"to\":\"build\",\"from\":\"test\"}],\"nodes\":[{\"labels\":[\"build\"],\"priority\":2,\"kind\":\"task\",\"title\":\"Build {{project}}\",\"name\":\"build\"},{\"labels\":[],\"priority\":1,\"kind\":\"task\",\"title\":\"Test {{project}}\",\"name\":\"test\"}],\"variables\":[{\"required\":true,\"name\":\"project\"}]}"
  let second = should.be_ok(service.register(workspace, reordered))
  field(first, "hash") |> should.equal(field(second, "hash"))
  should.be_ok(service.list(workspace))
  |> json.to_string
  |> string.contains("release")
  |> should.equal(True)
  should.be_ok(service.show(workspace, field(first, "hash")))
  |> json.to_string
  |> string.contains("Build {{project}}")
  |> should.equal(True)
}

pub fn templates_validate_and_registration_is_content_idempotent_test() {
  let workspace = workspace_registry
  reset(workspace)
  service.register(workspace, invalid_template) |> should.be_error
  should.be_ok(service.list(workspace))
  |> json.to_string
  |> should.equal("[]")

  let first = should.be_ok(service.register(workspace, valid_template))
  let second = should.be_ok(service.register(workspace, valid_template))
  field(first, "hash") |> should.equal(field(second, "hash"))
  should.be_ok(service.list(workspace))
  |> json.to_string
  |> string.contains("release")
  |> should.equal(True)
}

pub fn instantiation_is_atomic_idempotent_and_provenance_is_queryable_test() {
  let workspace = workspace_instance
  reset(workspace)
  let template = should.be_ok(service.register(workspace, valid_template))
  let hash = field(template, "hash")

  service.instantiate(workspace, hash, "missing", []) |> should.be_error
  should.be_ok(mnesia_store.current_store(workspace))
  |> task_store.current_tasks
  |> list.length
  |> should.equal(0)

  let first =
    should.be_ok(
      service.instantiate(workspace, hash, "release-1", [
        "project=bankai",
      ]),
    )
  let replay =
    should.be_ok(
      service.instantiate(workspace, hash, "release-1", [
        "project=bankai",
      ]),
    )
  let current_before_conflict =
    should.be_ok(mnesia_store.current_store(workspace))
    |> task_store.current_tasks
    |> list.length
  json.to_string(first)
  |> string.contains("\"replayed\":false")
  |> should.equal(True)
  json.to_string(replay)
  |> string.contains("\"replayed\":true")
  |> should.equal(True)
  service.instantiate(workspace, hash, "release-1", ["project=other"])
  |> should.be_error
  should.be_ok(mnesia_store.current_store(workspace))
  |> task_store.current_tasks
  |> list.length
  |> should.equal(current_before_conflict)

  let instance_id = field(first, "instance_id")
  let instance = should.be_ok(service.instance(workspace, instance_id))
  let build_id = task_id_for_node(instance, "build")
  molecule_store.provenance(workspace, build_id)
  |> should.be_ok
  |> should.equal(#(hash, instance_id, "build"))
}

pub fn composition_progress_current_and_distillation_are_views_test() {
  let workspace = workspace_progress
  reset(workspace)
  let template = should.be_ok(service.register(workspace, valid_template))
  let hash = field(template, "hash")
  let composed = should.be_ok(service.compose(workspace, "double", hash, hash))
  json.to_string(composed) |> string.contains("double") |> should.equal(True)
  let composed_hash = field(composed, "hash")
  composed_hash |> should.not_equal(hash)
  let composed_instance =
    should.be_ok(
      service.instantiate(workspace, composed_hash, "double-progress", [
        "project=bankai",
      ]),
    )
  let composed_detail =
    should.be_ok(service.instance(
      workspace,
      field(composed_instance, "instance_id"),
    ))
  json.to_string(composed_detail)
  |> string.contains("right.build")
  |> should.equal(True)

  let created =
    should.be_ok(
      service.instantiate(workspace, hash, "progress", [
        "project=bankai",
      ]),
    )
  let instance_id = field(created, "instance_id")
  let current = should.be_ok(service.current(workspace, instance_id))
  json.to_string(current)
  |> string.contains("Build bankai")
  |> should.equal(True)
  json.to_string(current)
  |> string.contains("Test bankai")
  |> should.equal(False)

  let build_id = task_id_for_node(created, "build")
  let _ = should.be_ok(daemon_store.update(workspace, build_id, "completed"))
  should.be_ok(service.current(workspace, instance_id))
  |> json.to_string
  |> string.contains("Test bankai")
  |> should.equal(True)
  should.be_ok(service.progress(workspace, instance_id))
  |> json.to_string
  |> string.contains("\"completed\":1")
  |> should.equal(True)
  should.be_ok(service.distill(workspace, instance_id))
  |> json.to_string
  |> string.contains("\"source_history_preserved\":true")
  |> should.equal(True)
}

pub fn molecule_protocol_authorization_and_mcp_catalog_are_consistent_test() {
  let workspace = workspace_protocol
  reset(workspace)
  let read = should.be_ok(service_auth.mint(workspace, "read", 3600))
  let write = should.be_ok(service_auth.mint(workspace, "write", 3600))
  let denied =
    "{\"method\":\"molecule_register\",\"params\":["
    <> json.to_string(json.string(valid_template))
    <> "],\"token\":\""
    <> read
    <> "\",\"id\":1}"
  socket.handle_authenticated_line(workspace, denied)
  |> string.contains("capability denied")
  |> should.equal(True)
  let allowed =
    "{\"method\":\"molecule_register\",\"params\":["
    <> json.to_string(json.string(valid_template))
    <> "],\"token\":\""
    <> write
    <> "\",\"id\":2}"
  socket.handle_authenticated_line(workspace, allowed)
  |> string.contains("\\\"ok\\\"")
  |> should.equal(True)

  mcp.handle_message(
    workspace,
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"tools/list\"}",
  )
  |> string.contains("molecule_instantiate")
  |> should.equal(True)
}
