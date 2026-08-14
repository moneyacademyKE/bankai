import bankai/daemon_store
import bankai/mnesia_store
import bankai/rules/service
import bankai/rules/store
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

const workspace = "/tmp/bankai_rule_service_test"

fn wipe() {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = store.init(workspace)
  let _ = store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

fn rule_hash(value: json.Json) -> String {
  let rendered = json.to_string(value)
  case string.split(rendered, "\"hash\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [hash, ..] -> hash
        [] -> ""
      }
    _ -> ""
  }
}

fn task_id(value: json.Json) -> String {
  let rendered = json.to_string(value)
  case string.split(rendered, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [id, ..] -> id
        [] -> ""
      }
    _ -> ""
  }
}

pub fn rule_source_approval_and_audit_survive_reinitialization_test() {
  wipe()
  let registered =
    should.be_ok(service.register(workspace, "identity", "(lam x x)"))
  let hash = rule_hash(registered)
  let _ = should.be_ok(service.approve(workspace, hash))
  let _ =
    should.be_ok(
      service.evaluate(workspace, hash, ["--caller", "restart-check"]),
    )

  let _ = should.be_ok(mnesia_store.init(workspace))
  let _ = should.be_ok(store.init(workspace))
  let shown = should.be_ok(service.show(workspace, hash))
  json.to_string(shown)
  |> string.contains("\"approved\":true")
  |> should.be_true
  let audit = should.be_ok(service.audits(workspace, hash))
  json.to_string(audit) |> string.contains("restart-check") |> should.be_true
}

pub fn unapproved_and_revoked_rules_are_denied_and_audited_test() {
  wipe()
  let registered =
    should.be_ok(service.register(workspace, "identity", "(lam x x)"))
  let hash = rule_hash(registered)

  let denied = service.evaluate(workspace, hash, ["--caller", "agent-a"])
  let message = should.be_error(denied)
  message |> string.contains("not approved") |> should.be_true
  let denied_audits = should.be_ok(service.audits(workspace, hash))
  json.to_string(denied_audits)
  |> string.contains("\"outcome\":\"error\"")
  |> should.be_true

  let _ = should.be_ok(service.approve(workspace, hash))
  let _ = should.be_ok(service.revoke(workspace, hash))
  service.evaluate(workspace, hash, []) |> should.be_error
  let audit = should.be_ok(service.audits(workspace, hash))
  json.to_string(audit) |> string.contains("\"sequence\"") |> should.be_true
}

pub fn malformed_rule_input_is_audited_without_task_mutation_test() {
  wipe()
  let _ = should.be_ok(daemon_store.boot(workspace))
  let task = should.be_ok(daemon_store.create(workspace, "Unchanged task", []))
  let id = task_id(task)
  let before = should.be_ok(mnesia_store.get_current(workspace, id))

  let registered = should.be_ok(service.register(workspace, "bad", "("))
  let hash = rule_hash(registered)
  let _ = should.be_ok(service.approve(workspace, hash))
  service.evaluate(workspace, hash, ["--task", id]) |> should.be_error

  let after = should.be_ok(mnesia_store.get_current(workspace, id))
  after.content_hash |> should.equal(before.content_hash)
  let audit = should.be_ok(service.audits(workspace, hash))
  json.to_string(audit)
  |> string.contains("\"outcome\":\"error\"")
  |> should.be_true
}

pub fn approved_rule_uses_immutable_task_view_without_mutating_task_test() {
  wipe()
  let _ = should.be_ok(daemon_store.boot(workspace))
  let task = should.be_ok(daemon_store.create(workspace, "Rule input task", []))
  let id = task_id(task)
  let before = should.be_ok(mnesia_store.get_current(workspace, id))

  let registered =
    should.be_ok(service.register(workspace, "identity", "(lam x x)"))
  let hash = rule_hash(registered)
  let _ = should.be_ok(service.approve(workspace, hash))
  let result =
    should.be_ok(
      service.evaluate(workspace, hash, ["--caller", "agent-b", "--task", id]),
    )
  json.to_string(result) |> string.contains("Rule input task") |> should.be_true

  let after = should.be_ok(mnesia_store.get_current(workspace, id))
  after.content_hash |> should.equal(before.content_hash)
  let versions = should.be_ok(mnesia_store.version_store(workspace))
  task_store.list(versions) |> list.length |> should.equal(1)
}

pub fn socket_rule_contract_uses_stable_envelopes_test() {
  wipe()
  case
    socket.handle_request(
      workspace,
      socket.Request("rule_register", ["identity", "(lam x x)"]),
    )
  {
    socket.OkResponse(value) ->
      value |> string.contains("\"ok\"") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }

  case socket.handle_request(workspace, socket.Request("rule_list", [])) {
    socket.OkResponse(value) ->
      value |> string.contains("identity") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
}
