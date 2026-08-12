import bankai/cluster
import bankai/daemon_store
import bankai/mnesia_store
import bankai/socket
import bankai/types
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_cluster_command_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace <> "/.bankai")
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = cluster.reset_for_test(workspace)
  let _ =
    simplifile.write(
      cluster_profile(),
      to: workspace <> "/.bankai/bankai-platform.json",
    )
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  Nil
}

fn cluster_profile() -> String {
  "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"test-rig\",\"node_id\":\"test-node\"}"
}

pub fn cluster_leases_have_one_winner_are_idempotent_and_fence_stale_holders_test() {
  reset()
  let first =
    should.be_ok(cluster.claim(
      workspace,
      "bk-claim",
      "alice",
      "head-a",
      "head-b",
      0,
    ))
  let cluster.Admission(first_fence, first_index, first_idempotent, _) = first
  first_idempotent |> should.be_false
  first_fence |> should.equal(1)
  first_index |> should.equal(0)

  let retry =
    should.be_ok(cluster.claim(
      workspace,
      "bk-claim",
      "alice",
      "head-a",
      "head-b",
      1,
    ))
  let cluster.Admission(retry_fence, retry_index, retry_idempotent, _) = retry
  retry_idempotent |> should.be_true
  retry_fence |> should.equal(first_fence)
  retry_index |> should.equal(first_index)

  cluster.claim(workspace, "bk-claim", "bob", "head-a", "head-b", 1)
  |> should.be_error

  let replacement =
    should.be_ok(cluster.claim(
      workspace,
      "bk-claim",
      "bob",
      "head-b",
      "head-c",
      300_000_000_001,
    ))
  let cluster.Admission(replacement_fence, _, replacement_idempotent, _) =
    replacement
  replacement_idempotent |> should.be_false
  replacement_fence |> should.equal(2)
  cluster.validate_fence(workspace, "bk-claim", first_fence) |> should.be_error
  cluster.validate_fence(workspace, "bk-claim", replacement_fence)
  |> should.be_ok

  let transition =
    should.be_ok(cluster.transition(
      workspace,
      "bk-claim",
      "head-c",
      "head-d",
      replacement_fence,
      300_000_000_002,
    ))
  let cluster.Admission(transition_fence, _, transition_idempotent, _) =
    transition
  transition_fence |> should.equal(replacement_fence)
  transition_idempotent |> should.be_false

  cluster.transition(
    workspace,
    "bk-claim",
    "head-d",
    "head-e",
    first_fence,
    300_000_000_003,
  )
  |> should.be_error
}

pub fn cluster_status_has_explicit_read_index_and_local_status_is_honest_test() {
  reset()
  let _ =
    should.be_ok(cluster.claim(workspace, "bk-status", "alice", "a", "b", 0))
  let status = should.be_ok(cluster.status(workspace))
  let cluster.Status(mode, _, commit, read, quorum, leases) = status
  mode |> should.equal(cluster.Cluster("test-rig", "test-node"))
  quorum |> should.equal("healthy")
  leases |> should.equal(1)
  commit |> should.equal(read)

  let no_quorum_ws = "/tmp/bankai_cluster_no_quorum_test"
  let _ = simplifile.create_directory_all(no_quorum_ws <> "/.bankai")
  let _ =
    simplifile.write(
      cluster_profile(),
      to: no_quorum_ws <> "/.bankai/bankai-platform.json",
    )
  let _ =
    should.be_ok(cluster.claim(
      no_quorum_ws,
      "bk-no-quorum",
      "alice",
      "a",
      "b",
      0,
    ))
  let _ = should.be_ok(cluster.force_no_quorum_for_test(no_quorum_ws))
  cluster.status(no_quorum_ws) |> should.be_error
  cluster.claim(no_quorum_ws, "bk-no-quorum", "bob", "b", "c", 1)
  |> should.be_error

  let local_json =
    cluster.status_json(cluster.Status(cluster.Local, "", -1, -1, "local", 0))
    |> json.to_string
  local_json |> string.contains("\"mode\":\"local\"") |> should.be_true
  local_json |> string.contains("\"commit_index\":-1") |> should.be_true
}

fn id_from_json(value: json.Json) -> String {
  case string.split(json.to_string(value), "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [id, ..] -> id
        [] -> ""
      }
    _ -> ""
  }
}

pub fn clustered_claim_materializes_once_and_requires_the_current_fence_test() {
  reset()
  let _ = should.be_ok(daemon_store.boot(workspace))
  let created =
    should.be_ok(daemon_store.create(workspace, "Clustered claim", []))
  let id = id_from_json(created)

  let claim = should.be_ok(daemon_store.claim(workspace, id, ["alice"]))
  let rendered = json.to_string(claim)
  rendered |> string.contains("\"clustered\":true") |> should.be_true
  rendered |> string.contains("\"fence\":1") |> should.be_true

  daemon_store.claim(workspace, id, ["bob"]) |> should.be_error
  daemon_store.update(workspace, id, "completed") |> should.be_error
  let completed =
    should.be_ok(daemon_store.update_fenced(workspace, id, "completed", "1"))
  json.to_string(completed)
  |> string.contains("\"status\":\"completed\"")
  |> should.be_true

  let stored = should.be_ok(mnesia_store.get_current(workspace, id))
  stored.status |> should.equal(types.Completed)

  let socket_fenced =
    socket.handle_request(
      workspace,
      socket.Request("update", [id, "--fence", "1", "completed"]),
    )
  case socket_fenced {
    socket.ErrorResponse(message) ->
      message |> string.contains("stale_fence") |> should.be_true
    socket.OkResponse(value) ->
      value |> string.contains("completed") |> should.be_true
  }

  let socket_status =
    socket.handle_request(workspace, socket.Request("cluster_status", []))
  case socket_status {
    socket.OkResponse(value) ->
      value |> string.contains("\"cluster\":{") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
  let status_value = should.be_ok(daemon_store.cluster_status(workspace))
  json.to_string(status_value)
  |> string.contains("\"recovery\":\"recovery-required\"")
  |> should.be_true
  let doctor = should.be_ok(daemon_store.doctor(workspace))
  json.to_string(doctor)
  |> string.contains("\"recovery\":\"recovery-required\"")
  |> should.be_true
}
