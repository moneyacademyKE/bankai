import aarondb/distributed_harness
import bankai/cluster
import bankai/daemon_store
import bankai/mnesia_store
import bankai/platform_profile
import bankai/socket
import bankai/storage/store
import bankai/sync/jsonl
import bankai/types
import gleam/json
import gleam/list
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const local_workspace = "/tmp/bankai_platform_local_rehearsal"

fn reset_local() -> Nil {
  let _ = simplifile.create_directory_all(local_workspace <> "/.bankai")
  let _ = mnesia_store.init(local_workspace)
  let _ = mnesia_store.reset_workspace_for_test(local_workspace)
  let _ = simplifile.write("", to: local_workspace <> "/tasks.jsonl")
  Nil
}

pub fn distributed_harness_schedules_preserve_claim_safety_invariants_test() {
  [11, 23, 37, 41]
  |> list.each(fn(seed) {
    let run =
      distributed_harness.replay(seed, [
        distributed_harness.Leaders(1, ["node-a"]),
        distributed_harness.Applied(7, 1),
        distributed_harness.Fence("bk-claim", 2, 2),
        distributed_harness.RecoveryAlarm(True),
      ])
    distributed_harness.passed(run) |> should.be_true
  })

  let unsafe =
    distributed_harness.replay(11, [
      distributed_harness.Leaders(1, ["node-a", "node-b"]),
      distributed_harness.Applied(7, 2),
      distributed_harness.Fence("bk-claim", 3, 2),
      distributed_harness.RecoveryAlarm(False),
    ])
  distributed_harness.passed(unsafe) |> should.be_false
  distributed_harness.inspect(unsafe) |> list.length |> should.equal(4)
}

pub fn local_mnesia_export_rebootstrap_preserves_immutable_history_test() {
  reset_local()
  let _ = should.be_ok(daemon_store.boot(local_workspace))
  let created =
    should.be_ok(daemon_store.create(local_workspace, "Migration fixture", []))
  let id = id_from_json(json.to_string(created))
  let _ = should.be_ok(daemon_store.update(local_workspace, id, "completed"))
  let before = should.be_ok(mnesia_store.version_store(local_workspace))
  store_length(before) |> should.equal(2)
  let _ = should.be_ok(daemon_store.export_jsonl(local_workspace))
  let exported =
    should.be_ok(jsonl.load(from: local_workspace <> "/tasks.jsonl"))
  exported |> list.length |> should.equal(2)

  let imported_workspace = "/tmp/bankai_platform_import_rehearsal"
  let _ = simplifile.create_directory_all(imported_workspace <> "/.bankai")
  let _ = mnesia_store.init(imported_workspace)
  let _ = mnesia_store.reset_workspace_for_test(imported_workspace)
  let _ = simplifile.write("", to: imported_workspace <> "/tasks.jsonl")
  let _ = should.be_ok(daemon_store.boot(imported_workspace))
  let _ =
    should.be_ok(daemon_store.import_jsonl(
      imported_workspace,
      local_workspace <> "/tasks.jsonl",
    ))
  let restored = should.be_ok(mnesia_store.version_store(imported_workspace))
  store_length(restored) |> should.equal(2)
  let current = should.be_ok(mnesia_store.get_current(imported_workspace, id))
  current.status |> should.equal(types.Completed)
}

pub fn local_profile_remains_honest_without_cluster_claims_test() {
  reset_local()
  let _ = should.be_ok(daemon_store.boot(local_workspace))
  let status = should.be_ok(daemon_store.cluster_status(local_workspace))
  json.to_string(status)
  |> string.contains("\"mode\":\"local\"")
  |> should.be_true
  json.to_string(status)
  |> string.contains("\"recovery\":\"healthy\"")
  |> should.be_true
  cluster.claim(local_workspace, "bk-local", "alice", "a", "b", 0)
  |> should.be_error
}

pub fn clustered_profile_without_transport_refuses_recovery_and_mutation_admission_test() {
  let workspace = "/tmp/bankai_platform_clustered_rehearsal"
  let _ = simplifile.create_directory_all(workspace <> "/.bankai")
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ =
    simplifile.write(
      "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"rig-rehearsal\",\"node_id\":\"node-a\"}",
      to: workspace <> "/.bankai/bankai-platform.json",
    )
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  let _ = should.be_ok(daemon_store.boot(workspace))
  let status = should.be_ok(daemon_store.cluster_status(workspace))
  json.to_string(status)
  |> string.contains("\"recovery\":\"recovery-required\"")
  |> should.be_true
  let socket_status =
    socket.handle_request(workspace, socket.Request("cluster_status", []))
  case socket_status {
    socket.OkResponse(value) ->
      value |> string.contains("recovery-required") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
  platform_profile.load(workspace)
  |> should.be_ok
}

fn store_length(value: store.Store) -> Int {
  store.list(value) |> list.length
}

fn id_from_json(value: String) -> String {
  case string.split(value, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [id, ..] -> id
        [] -> ""
      }
    _ -> ""
  }
}
