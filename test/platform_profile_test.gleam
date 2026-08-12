import bankai/platform_profile
import gleam/json
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn missing_profile_is_local_and_names_the_ownership_contract_test() {
  let profile = platform_profile.default()
  profile.mode |> should.equal(platform_profile.Local)
  profile.task_authority |> should.equal("bankai-mnesia")
  profile.projection_source |> should.equal("aarondb-changefeed")
  profile.interchange |> should.equal("jsonl")
  platform_profile.require_local_daemon(profile) |> should.be_ok
}

pub fn clustered_profile_requires_identity_and_is_refused_by_local_daemon_test() {
  let valid =
    "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"rig-a\",\"node_id\":\"node-a\"}"
  let profile = should.be_ok(platform_profile.from_json(valid))
  profile.mode |> should.equal(platform_profile.Clustered)
  platform_profile.require_local_daemon(profile) |> should.be_error

  let missing_node =
    "{\"schema_version\":1,\"mode\":\"clustered\",\"task_authority\":\"bankai-mnesia\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\",\"cluster_id\":\"rig-a\"}"
  platform_profile.from_json(missing_node) |> should.be_error
}

pub fn profile_rejects_an_authority_or_schema_downgrade_test() {
  let wrong_authority =
    "{\"schema_version\":1,\"mode\":\"local\",\"task_authority\":\"aarondb\",\"projection_source\":\"aarondb-changefeed\",\"interchange\":\"jsonl\"}"
  platform_profile.from_json(wrong_authority) |> should.be_error

  let profile = platform_profile.default()
  let serialized = platform_profile.to_json(profile) |> json.to_string
  serialized |> string.contains("\"mode\":\"local\"") |> should.be_true
  serialized
  |> string.contains("\"task_authority\":\"bankai-mnesia\"")
  |> should.be_true
  profile.cluster_id |> should.equal(option.None)
}
