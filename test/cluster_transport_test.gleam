import bankai/cluster_transport
import bankai/platform_profile
import gleam/json
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_cluster_transport_test"

fn profile() -> platform_profile.Profile {
  should.be_ok(platform_profile.from_json(
    "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"rig-a\",\"node_id\":\"node-a\"}",
  ))
}

fn valid_transport() -> String {
  "{\"schema_version\":1,\"cluster_id\":\"rig-a\",\"node_id\":\"node-a\",\"issuer\":\"bankai-ca\",\"local_fingerprint\":\"fingerprint-a\",\"members\":[{\"node_id\":\"node-a\",\"fingerprint\":\"fingerprint-a\"}],\"max_rpc_bytes\":1048576,\"max_attempts\":3,\"timeout_ms\":5000}"
}

fn reset(config: String) -> Nil {
  let _ = simplifile.create_directory_all(workspace <> "/.bankai")
  let _ = simplifile.write(config, to: cluster_transport.path(workspace))
  Nil
}

pub fn authenticated_cluster_transport_requires_bound_profile_and_identity_test() {
  reset(valid_transport())
  cluster_transport.require_ready(workspace, profile()) |> should.be_ok
  let status = cluster_transport.diagnose(workspace, profile())
  json.to_string(cluster_transport.status_json(status))
  |> string.contains("\"state\":\"configured\"")
  |> should.be_true
  json.to_string(cluster_transport.status_json(status))
  |> string.contains("\"transport\":\"beam-distribution-tls\"")
  |> should.be_true
}

pub fn missing_or_mismatched_cluster_transport_is_recovery_required_test() {
  let _ = simplifile.create_directory_all(workspace <> "/.bankai")
  let _ = simplifile.write("", to: cluster_transport.path(workspace))
  let status = cluster_transport.diagnose(workspace, profile())
  json.to_string(cluster_transport.status_json(status))
  |> string.contains("\"state\":\"recovery-required\"")
  |> should.be_true

  let mismatched =
    "{\"schema_version\":1,\"cluster_id\":\"rig-b\",\"node_id\":\"node-a\",\"issuer\":\"bankai-ca\",\"local_fingerprint\":\"fingerprint-a\",\"members\":[{\"node_id\":\"node-a\",\"fingerprint\":\"fingerprint-a\"}],\"max_rpc_bytes\":1048576,\"max_attempts\":3,\"timeout_ms\":5000}"
  reset(mismatched)
  cluster_transport.require_ready(workspace, profile()) |> should.be_error
}

pub fn local_profile_has_no_transport_recovery_requirement_test() {
  let local = platform_profile.default()
  let status = cluster_transport.diagnose(workspace, local)
  json.to_string(cluster_transport.status_json(status))
  |> string.contains("\"state\":\"not-applicable\"")
  |> should.be_true
}
