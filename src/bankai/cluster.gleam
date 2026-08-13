//// Clustered command admission for Bankai.
////
//// Mnesia remains the materialized task/version store. This module admits a
//// cluster-visible mutation before Mnesia applies it idempotently by command ID.
//// Local mode deliberately never calls this surface.

import bankai/platform_profile
import gleam/json
import gleam/option
import gleam/result

pub type Mode {
  Local
  Cluster(cluster_id: String, node_id: String)
}

pub type Admission {
  Admission(fence: Int, commit_index: Int, idempotent: Bool, command_id: String)
}

pub type Status {
  Status(
    mode: Mode,
    leader: String,
    commit_index: Int,
    read_index: Int,
    quorum: String,
    lease_count: Int,
  )
}

@external(erlang, "bankai_cluster_ffi", "claim")
fn ffi_claim(
  workspace: String,
  cluster_id: String,
  node_id: String,
  task_id: String,
  holder: String,
  expected_hash: String,
  replacement_hash: String,
  now: Int,
) -> Result(#(Int, Int, Bool, String), String)

@external(erlang, "bankai_cluster_ffi", "transition")
fn ffi_transition(
  workspace: String,
  cluster_id: String,
  node_id: String,
  task_id: String,
  expected_hash: String,
  replacement_hash: String,
  fence: Int,
  now: Int,
) -> Result(#(Int, Int, Bool, String), String)

@external(erlang, "bankai_cluster_ffi", "validate_fence")
fn ffi_validate_fence(
  workspace: String,
  task_id: String,
  fence: Int,
) -> Result(Nil, String)

@external(erlang, "bankai_cluster_ffi", "status")
fn ffi_status(
  workspace: String,
  cluster_id: String,
  node_id: String,
) -> Result(#(String, Int, Int, String, Int), String)

@external(erlang, "bankai_cluster_ffi", "reset_for_test")
fn ffi_reset_for_test(workspace: String) -> Result(Nil, String)

@external(erlang, "bankai_cluster_ffi", "force_no_quorum_for_test")
fn ffi_force_no_quorum_for_test(workspace: String) -> Result(Nil, String)

pub fn mode(workspace: String) -> Result(Mode, String) {
  platform_profile.load(workspace)
  |> result.map(fn(profile) {
    case profile.mode, profile.cluster_id, profile.node_id {
      platform_profile.Local, _, _ -> Local
      platform_profile.Clustered, option.Some(cluster_id), option.Some(node_id)
      -> Cluster(cluster_id, node_id)
      platform_profile.Clustered, _, _ -> Local
    }
  })
}

/// Quorum-admit a conditional claim and lease acquire. The Mnesia task CAS uses
/// the returned command ID exactly once; retried requests receive this admission
/// rather than a second lease or task write.
pub fn claim(
  workspace: String,
  task_id: String,
  holder: String,
  expected_hash: String,
  replacement_hash: String,
  now: Int,
) -> Result(Admission, String) {
  profile(workspace)
  |> result.try(fn(config) {
    ffi_claim(
      workspace,
      config.0,
      config.1,
      task_id,
      holder,
      expected_hash,
      replacement_hash,
      now,
    )
    |> result.map(admission_from_raw)
  })
}

/// Quorum-admit a claimant-owned transition. It validates the current lease
/// fence before Mnesia performs the expected-head CAS under the command ID.
pub fn transition(
  workspace: String,
  task_id: String,
  expected_hash: String,
  replacement_hash: String,
  fence: Int,
  now: Int,
) -> Result(Admission, String) {
  profile(workspace)
  |> result.try(fn(config) {
    ffi_transition(
      workspace,
      config.0,
      config.1,
      task_id,
      expected_hash,
      replacement_hash,
      fence,
      now,
    )
    |> result.map(admission_from_raw)
  })
}

pub fn validate_fence(
  workspace: String,
  task_id: String,
  fence: Int,
) -> Result(Nil, String) {
  ffi_validate_fence(workspace, task_id, fence)
}

/// A clustered status includes a ReadIndex confirmation. Callers can distinguish
/// a leader-confirmed read from local-mode Mnesia reads without inspecting logs.
pub fn status(workspace: String) -> Result(Status, String) {
  mode(workspace)
  |> result.try(fn(current) {
    case current {
      Local -> Ok(Status(Local, "", -1, -1, "local", 0))
      Cluster(cluster_id, node_id) ->
        ffi_status(workspace, cluster_id, node_id)
        |> result.map(fn(raw) {
          let #(leader, commit_index, read_index, quorum, lease_count) = raw
          Status(current, leader, commit_index, read_index, quorum, lease_count)
        })
    }
  })
}

pub fn status_json(status: Status) -> json.Json {
  let Status(mode, leader, commit_index, read_index, quorum, lease_count) =
    status
  json.object([
    #("mode", json.string(mode_name(mode))),
    #(
      "leader",
      json.nullable(
        case leader == "" {
          True -> option.None
          False -> option.Some(leader)
        },
        of: json.string,
      ),
    ),
    #("commit_index", json.int(commit_index)),
    #("read_index", json.int(read_index)),
    #("quorum", json.string(quorum)),
    #("lease_count", json.int(lease_count)),
  ])
}

pub fn reset_for_test(workspace: String) -> Result(Nil, String) {
  ffi_reset_for_test(workspace)
}

pub fn force_no_quorum_for_test(workspace: String) -> Result(Nil, String) {
  ffi_force_no_quorum_for_test(workspace)
}

fn profile(workspace: String) -> Result(#(String, String), String) {
  mode(workspace)
  |> result.try(fn(current) {
    case current {
      Local -> Error("clustered command requires a clustered Bankai profile")
      Cluster(cluster_id, node_id) -> Ok(#(cluster_id, node_id))
    }
  })
}

fn admission_from_raw(raw: #(Int, Int, Bool, String)) -> Admission {
  let #(fence, commit_index, idempotent, command_id) = raw
  Admission(fence, commit_index, idempotent, command_id)
}

fn mode_name(mode: Mode) -> String {
  case mode {
    Local -> "local"
    Cluster(_, _) -> "clustered"
  }
}
