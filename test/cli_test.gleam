import bankai/cli
import bankai/serde
import bankai/socket
import bankai/types
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleamunison/identity
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

const ws_e2e = "/tmp/bankai_cli_e2e"

const ws_inspect = "/tmp/bankai_cli_inspect"

const ws_socket = "/tmp/bankai_cli_socket"

const ws_status = "/tmp/bankai_cli_status"

const ws_dataloss = "/tmp/bankai_cli_dataloss"

const ws_g12 = "/tmp/bankai_cli_g12"

const ws_show = "/tmp/bankai_cli_show"

const ws_dep = "/tmp/bankai_cli_dep"

const ws_claim = "/tmp/bankai_cli_claim"

const ws_env = "/tmp/bankai_cli_env"

/// G9: unwrap a {"ok": <task>} envelope into the Task. (Commands now return
/// envelopes; tests decode via this instead of serde.task_from_json_string.)
fn ok_task_decoder() -> decode.Decoder(types.Task) {
  use task <- decode.field("ok", serde.task_decoder())
  decode.success(task)
}

fn task_from_output(output: String) -> Result(types.Task, json.DecodeError) {
  json.parse(from: output, using: ok_task_decoder())
}

/// Full lifecycle: init -> create -> ready -> update -> inspect.
pub fn cli_e2e_smoke_test() {
  let _ = cli.run_in(ws_e2e, ["init"])
  let created = cli.run_in(ws_e2e, ["create", "Ship the bankai MVP"])
  let task = should.be_ok(task_from_output(created))

  task.title
  |> should.equal("Ship the bankai MVP")

  // A freshly-created Open task with no blockers is ready.
  cli.run_in(ws_e2e, ["ready"])
  |> string.contains("Ship the bankai MVP")
  |> should.be_true

  // Mark it completed; it should no longer be ready.
  cli.run_in(ws_e2e, ["update", task.id, "completed"])
  |> string.contains("completed")
  |> should.be_true

  cli.run_in(ws_e2e, ["ready"])
  |> string.contains("Ship the bankai MVP")
  |> should.be_false
}

/// The content hash from `create` is inspectable end to end.
pub fn cli_inspect_roundtrip_test() {
  let _ = cli.run_in(ws_inspect, ["init"])
  let created = cli.run_in(ws_inspect, ["create", "Inspectable task"])
  let task = should.be_ok(task_from_output(created))
  let hash = identity.hash_to_debug_string(task.content_hash)

  cli.run_in(ws_inspect, ["inspect", hash])
  |> string.contains("Inspectable task")
  |> should.be_true
}

pub fn prime_emits_agent_prompt_test() {
  cli.run_in(ws_e2e, ["prime"])
  |> string.contains("content-addressed")
  |> should.be_true
}

/// JSON-RPC protocol round-trips through the socket/daemon handler.
pub fn socket_jsonrpc_roundtrip_test() {
  let _ = socket.handle_request(ws_socket, socket.Request("init", []))
  let _ =
    socket.handle_request(
      ws_socket,
      socket.Request("create", ["socket-driven"]),
    )
  let resp = socket.handle_request(ws_socket, socket.Request("ready", []))

  case resp {
    socket.OkResponse(value) ->
      value
      |> string.contains("socket-driven")
      |> should.be_true
    socket.ErrorResponse(message) ->
      message
      |> should.equal("should not error")
  }
}

pub fn socket_unknown_method_errors_test() {
  case socket.handle_request(ws_socket, socket.Request("frobnicate", [])) {
    socket.ErrorResponse(_) -> should.be_true(True)
    socket.OkResponse(_) -> should.be_true(False)
  }
}

/// BUG-02 regression: `update` must accept ALL five status variants.
pub fn cli_update_accepts_blocked_and_closed_test() {
  let _ = cli.run_in(ws_status, ["init"])
  let created = cli.run_in(ws_status, ["create", "All-status task"])
  let task = should.be_ok(task_from_output(created))

  // "blocked" must be accepted and round-trip through serde.
  cli.run_in(ws_status, ["update", task.id, "blocked"])
  |> task_from_output
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Blocked)

  // "closed" likewise.
  cli.run_in(ws_status, ["update", task.id, "closed"])
  |> task_from_output
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Closed)

  // An unknown status is still rejected.
  cli.run_in(ws_status, ["update", task.id, "frobnicated"])
  |> string.contains("invalid status")
  |> should.be_true
}

/// BUG-01 regression: updating one task must preserve every other task.
pub fn cli_update_preserves_sibling_tasks_test() {
  let _ = cli.run_in(ws_dataloss, ["init"])
  let created_a = cli.run_in(ws_dataloss, ["create", "Keep task A"])
  let a = should.be_ok(task_from_output(created_a))
  let _ = cli.run_in(ws_dataloss, ["create", "Keep task B"])

  cli.run_in(ws_dataloss, ["update", a.id, "completed"])
  |> task_from_output
  |> should.be_ok
  |> fn(t) { t.status }
  |> should.equal(types.Completed)

  cli.run_in(ws_dataloss, ["list"])
  |> string.contains("Keep task B")
  |> should.be_true

  cli.run_in(ws_dataloss, ["ready"])
  |> string.contains("Keep task B")
  |> should.be_true

  cli.run_in(ws_dataloss, ["ready"])
  |> string.contains("Keep task A")
  |> should.be_false
}

// ---------------------------------------------------------------------------
// Phase 1 (P0) — Beads-parity feature tests
// ---------------------------------------------------------------------------

/// G12: create produces a short hash-prefix id (bk-XXXX), not a timestamp.
pub fn create_uses_hash_prefix_id_test() {
  let _ = cli.run_in(ws_g12, ["init"])
  let created = cli.run_in(ws_g12, ["create", "Hashy"])
  let task = should.be_ok(task_from_output(created))

  string.starts_with(task.id, "bk-")
  |> should.be_true
  // "bk-" + 4 hex = 7 chars
  string.length(task.id)
  |> should.equal(7)
}

/// G2: show <id> returns the task by id.
pub fn show_returns_task_by_id_test() {
  let _ = cli.run_in(ws_show, ["init"])
  let created = cli.run_in(ws_show, ["create", "Showable"])
  let task = should.be_ok(task_from_output(created))

  let shown = cli.run_in(ws_show, ["show", task.id])
  let shown_task = should.be_ok(task_from_output(shown))
  shown_task.title
  |> should.equal("Showable")
}

/// G2: show on a missing id is an error envelope.
pub fn show_missing_is_error_envelope_test() {
  let _ = cli.run_in(ws_show, ["init"])
  cli.run_in(ws_show, ["show", "bk-nope"])
  |> string.starts_with("{\"error\"")
  |> should.be_true
}

/// G1: dep add wires a Blocks edge; a blocked task is not ready until its
/// blocker completes.
pub fn dep_add_wires_and_affects_ready_test() {
  let _ = cli.run_in(ws_dep, ["init"])
  let a =
    should.be_ok(
      task_from_output(cli.run_in(ws_dep, ["create", "Dependent A"])),
    )
  let b =
    should.be_ok(task_from_output(cli.run_in(ws_dep, ["create", "Blocker B"])))

  // a becomes blocked by b.
  let updated_a =
    should.be_ok(
      task_from_output(cli.run_in(ws_dep, ["dep", "add", a.id, b.id])),
    )
  list.length(updated_a.relationships)
  |> should.equal(1)

  // a is blocked by an Open b -> a is NOT ready.
  cli.run_in(ws_dep, ["ready"])
  |> string.contains("Dependent A")
  |> should.be_false

  // complete the blocker -> a becomes ready.
  let _ = cli.run_in(ws_dep, ["update", b.id, "completed"])
  cli.run_in(ws_dep, ["ready"])
  |> string.contains("Dependent A")
  |> should.be_true
}

/// G1: dep add rejects a cycle (graph.would_cycle).
pub fn dep_add_rejects_cycle_test() {
  let _ = cli.run_in(ws_dep, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws_dep, ["create", "A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws_dep, ["create", "B"])))
  // a -> b (a blocked by b). Then b -> a closes a cycle.
  let _ = cli.run_in(ws_dep, ["dep", "add", a.id, b.id])
  cli.run_in(ws_dep, ["dep", "add", b.id, a.id])
  |> string.contains("cycle")
  |> should.be_true
}

/// G1 / BUG-04: dep add of an existing edge is idempotent (hash unchanged).
pub fn dep_add_is_idempotent_test() {
  let _ = cli.run_in(ws_dep, ["init"])
  let a = should.be_ok(task_from_output(cli.run_in(ws_dep, ["create", "A"])))
  let b = should.be_ok(task_from_output(cli.run_in(ws_dep, ["create", "B"])))
  let once =
    should.be_ok(
      task_from_output(cli.run_in(ws_dep, ["dep", "add", a.id, b.id])),
    )
  let twice =
    should.be_ok(
      task_from_output(cli.run_in(ws_dep, ["dep", "add", a.id, b.id])),
    )
  identity.hash_equal(twice.content_hash, once.content_hash)
  |> should.be_true
}

/// G8: update <id> --claim <assignee> sets in_progress + assignee atomically.
pub fn claim_sets_in_progress_and_assignee_test() {
  let _ = cli.run_in(ws_claim, ["init"])
  let t =
    should.be_ok(
      task_from_output(cli.run_in(ws_claim, ["create", "Claimable"])),
    )
  let claimed =
    should.be_ok(
      task_from_output(
        cli.run_in(ws_claim, ["update", t.id, "--claim", "alice"]),
      ),
    )
  claimed.status
  |> should.equal(types.InProgress)
  claimed.assignee
  |> should.equal(option.Some("alice"))
}

/// G8: --claim with no assignee defaults to "agent".
pub fn claim_defaults_assignee_to_agent_test() {
  let _ = cli.run_in(ws_claim, ["init"])
  let t =
    should.be_ok(
      task_from_output(cli.run_in(ws_claim, ["create", "Claimable2"])),
    )
  let claimed =
    should.be_ok(
      task_from_output(cli.run_in(ws_claim, ["update", t.id, "--claim"])),
    )
  claimed.assignee
  |> should.equal(option.Some("agent"))
}

/// G9: success output is an {"ok": ...} envelope.
pub fn success_output_is_ok_envelope_test() {
  let _ = cli.run_in(ws_env, ["init"])
  cli.run_in(ws_env, ["create", "Env"])
  |> string.starts_with("{\"ok\"")
  |> should.be_true
}

/// G9: failure output is an {"error": ...} envelope.
pub fn error_output_is_error_envelope_test() {
  let _ = cli.run_in(ws_env, ["init"])
  cli.run_in(ws_env, ["show", "bk-missing"])
  |> string.starts_with("{\"error\"")
  |> should.be_true
}
