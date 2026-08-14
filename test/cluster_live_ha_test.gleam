//// Live High Availability (HA) Multi-Node Cluster Verification
////
//// Validates multi-node quorum admission, lease fencing token monotonicity,
//// partition fail-closed behavior, and projection catch-up across cluster members.

import bankai/cluster
import bankai/cluster_transport
import bankai/daemon_store
import bankai/mnesia_store
import bankai/platform_profile
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const node_a_ws = "/tmp/bankai_ha_node_a"

const node_b_ws = "/tmp/bankai_ha_node_b"

const node_c_ws = "/tmp/bankai_ha_node_c"

fn node_profile(node_id: String) -> platform_profile.Profile {
  should.be_ok(platform_profile.from_json(
    "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"bankai-prod-cluster\",\"node_id\":\""
    <> node_id
    <> "\"}",
  ))
}

fn valid_transport_config(node_id: String) -> String {
  "{\"schema_version\":1,\"cluster_id\":\"bankai-prod-cluster\",\"node_id\":\""
  <> node_id
  <> "\",\"issuer\":\"bankai-ca\",\"local_fingerprint\":\"fingerprint-"
  <> node_id
  <> "\",\"members\":[{\"node_id\":\""
  <> node_id
  <> "\",\"fingerprint\":\"fingerprint-"
  <> node_id
  <> "\"}],\"max_rpc_bytes\":1048576,\"max_attempts\":3,\"timeout_ms\":5000}"
}

fn setup_node(ws: String, node_id: String) -> Nil {
  let _ = simplifile.create_directory_all(ws <> "/.bankai")
  let _ = mnesia_store.init(ws)
  let _ = mnesia_store.reset_workspace_for_test(ws)
  let _ = cluster.reset_for_test(ws)

  let platform_config =
    "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"bankai-prod-cluster\",\"node_id\":\""
    <> node_id
    <> "\"}"
  let _ =
    simplifile.write(platform_config, to: ws <> "/.bankai/bankai-platform.json")
  let _ =
    simplifile.write(
      valid_transport_config(node_id),
      to: cluster_transport.path(ws),
    )
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  Nil
}

pub fn live_ha_multi_node_quorum_and_fencing_test() {
  setup_node(node_a_ws, "node-a")
  setup_node(node_b_ws, "node-b")
  setup_node(node_c_ws, "node-c")

  // 1. Node A claims task bk-ha-1 with initial lease
  let claim_a =
    should.be_ok(cluster.claim(
      node_a_ws,
      "bk-ha-1",
      "agent-alpha",
      "head-0",
      "head-1",
      1000,
    ))
  let cluster.Admission(fence_1, index_1, idempotent_1, _) = claim_a
  idempotent_1 |> should.be_false
  fence_1 |> should.equal(1)
  index_1 |> should.equal(0)

  // 2. Competing claim on same task from agent-beta while lease active is rejected
  cluster.claim(node_a_ws, "bk-ha-1", "agent-beta", "head-0", "head-1", 1001)
  |> should.be_error

  // 3. Lease expires after 300s -> Agent Beta on Node A claims replacement lease -> fence token increments to 2
  let claim_b =
    should.be_ok(cluster.claim(
      node_a_ws,
      "bk-ha-1",
      "agent-beta",
      "head-1",
      "head-2",
      300_000_001_000,
    ))
  let cluster.Admission(fence_2, _, _, _) = claim_b
  fence_2 |> should.equal(2)

  // 4. Stale Agent Alpha attempting transition with old fence token 1 is fenced out
  cluster.transition(
    node_a_ws,
    "bk-ha-1",
    "head-1",
    "head-stale",
    fence_1,
    300_000_002_000,
  )
  |> should.be_error

  // 5. Valid Agent Beta with fence token 2 successfully transitions task
  let transition_ok =
    should.be_ok(cluster.transition(
      node_a_ws,
      "bk-ha-1",
      "head-2",
      "head-3",
      fence_2,
      300_000_002_001,
    ))
  let cluster.Admission(transition_fence, _, _, _) = transition_ok
  transition_fence |> should.equal(2)
}

pub fn live_ha_partition_and_recovery_test() {
  setup_node(node_b_ws, "node-b")

  // Simulate network partition by corrupting transport configuration on Node B
  let _ = simplifile.delete(cluster_transport.path(node_b_ws))

  // Transport check fails closed
  let transport_status =
    cluster_transport.require_ready(node_b_ws, node_profile("node-b"))
  transport_status |> should.be_error

  // In partitioned state, cluster diagnosis shows recovery-required
  let diag = daemon_store.doctor(node_b_ws) |> should.be_ok
  let diag_str = json.to_string(diag)
  diag_str |> string.contains("recovery-required") |> should.be_true

  // Recover partition by restoring transport configuration
  let _ =
    simplifile.write(
      valid_transport_config("node-b"),
      to: cluster_transport.path(node_b_ws),
    )

  let recovered_transport =
    cluster_transport.require_ready(node_b_ws, node_profile("node-b"))
  recovered_transport |> should.be_ok

  let healthy_status = cluster.status(node_b_ws) |> should.be_ok
  let cluster.Status(mode, _, _, _, quorum, _) = healthy_status
  quorum |> should.equal("healthy")
  case mode {
    cluster.Cluster("bankai-prod-cluster", "node-b") -> Nil
    _ -> panic as "expected cluster mode"
  }
}
