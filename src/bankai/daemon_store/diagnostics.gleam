//// Daemon diagnostics and health reporting.
////
//// Aggregates Mnesia task authority integrity, cycle detection, cluster quorum status,
//// AaronDB projection health, and fail-closed transport diagnostics.

import aarondb/projection_index
import bankai/cluster
import bankai/cluster_transport
import bankai/graph
import bankai/mnesia_store
import bankai/platform_profile
import bankai/projections
import bankai/storage/store
import bankai/vector_bridge
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string

pub fn doctor(workspace: String) -> Result(json.Json, String) {
  case
    mnesia_store.current_store(workspace),
    mnesia_store.version_store(workspace),
    platform_profile.load(workspace)
  {
    Ok(current), Ok(versions), Ok(profile) -> {
      let tasks = store.current_tasks(current)
      let cycles = graph.cycle_edges(tasks)
      let missing =
        list.flat_map(tasks, fn(task) {
          task.relationships
          |> list.filter_map(fn(r) {
            case
              list.any(tasks, fn(candidate) { candidate.id == r.target_id })
            {
              True -> Error(Nil)
              False -> Ok(task.id <> " -> " <> r.target_id)
            }
          })
        })
      let projection = projection_diagnostics(workspace)
      let cluster_diag = cluster_diagnostics(workspace)
      let transport = cluster_transport.diagnose(workspace, profile)
      let recovery =
        recovery_state(profile, cluster_diag, projection, transport)
      Ok(
        json.object([
          #(
            "healthy",
            json.bool(
              list.is_empty(cycles)
              && list.is_empty(missing)
              && recovery == "healthy",
            ),
          ),
          #("tasks", json.int(list.length(tasks))),
          #("versions", json.int(list.length(store.list(versions)))),
          #("cycles", json.int(list.length(cycles))),
          #("missing_targets", json.int(list.length(missing))),
          #("mode", json.string(platform_profile.mode_name(profile.mode))),
          #("projection", projection),
          #("cluster", cluster_diag),
          #("transport", cluster_transport.status_json(transport)),
          #("recovery", json.string(recovery)),
          #("repair", json.string("none; diagnostics are read-only")),
        ]),
      )
    }
    Error(error), _, _ -> Error(error)
    _, Error(error), _ -> Error(error)
    _, _, Error(error) -> Error(error)
  }
}

pub fn cluster_status(workspace: String) -> Result(json.Json, String) {
  platform_profile.load(workspace)
  |> result.try(fn(profile) {
    cluster.status(workspace)
    |> result.map(fn(status) {
      let cluster_json = cluster.status_json(status)
      let transport = cluster_transport.diagnose(workspace, profile)
      json.object([
        #("cluster", cluster_json),
        #("transport", cluster_transport.status_json(transport)),
        #(
          "recovery",
          json.string(recovery_state(
            profile,
            cluster_json,
            projection_diagnostics(workspace),
            transport,
          )),
        ),
      ])
    })
  })
}

pub fn recovery_state(
  profile: platform_profile.Profile,
  cluster_diag: json.Json,
  projection: json.Json,
  transport: cluster_transport.TransportStatus,
) -> String {
  case profile.mode, transport {
    platform_profile.Clustered, cluster_transport.RecoveryRequired(_) ->
      "recovery-required"
    platform_profile.Clustered, _ ->
      case
        string.contains(json.to_string(cluster_diag), "\"quorum\":\"healthy\"")
        && string.contains(json.to_string(projection), "\"healthy\":true")
      {
        True -> "healthy"
        False -> "degraded"
      }
    platform_profile.Local, _ ->
      case string.contains(json.to_string(projection), "\"healthy\":true") {
        True -> "healthy"
        False -> "degraded"
      }
  }
}

pub fn cluster_diagnostics(workspace: String) -> json.Json {
  case cluster.status(workspace) {
    Ok(status) -> cluster.status_json(status)
    Error(error) ->
      json.object([
        #("mode", json.string("unavailable")),
        #("error", json.string(error)),
      ])
  }
}

pub fn projection_diagnostics(workspace: String) -> json.Json {
  case projections.runtime_status(workspace) {
    Ok(status) ->
      json.object([
        #("changefeed", projection_runtime_json(status)),
        #("vector_index", vector_projection_diagnostics(workspace)),
      ])
    Error(_) ->
      case projections.bootstrap(workspace) {
        Ok(view) ->
          json.object([
            #("healthy", json.bool(projections.healthy(view))),
            #("high_watermark", json.int(view.source.next_offset - 1)),
            #("mode", json.string("fresh-mnesia-rebuild")),
          ])
        Error(error) ->
          json.object([
            #("healthy", json.bool(False)),
            #("error", json.string(error)),
          ])
      }
  }
}

pub fn vector_projection_status(
  workspace: String,
) -> Result(json.Json, String) {
  vector_bridge.projection_status(workspace)
  |> result.map(vector_projection_status_json)
}

fn vector_projection_diagnostics(workspace: String) -> json.Json {
  case vector_projection_status(workspace) {
    Ok(status) -> status
    Error(error) ->
      json.object([
        #("health", json.string("unbuilt")),
        #("error", json.string(error)),
      ])
  }
}

fn projection_runtime_json(status: projections.RuntimeStatus) -> json.Json {
  let projections.RuntimeStatus(
    healthy,
    high_watermark,
    history_state,
    history_offset,
    history_lag,
    history_failure,
    text_state,
    text_offset,
    text_lag,
    text_failure,
    vector_state,
    vector_offset,
    vector_lag,
    vector_failure,
  ) = status
  json.object([
    #("healthy", json.bool(healthy)),
    #("high_watermark", json.int(high_watermark)),
    #("mode", json.string("daemon-runtime")),
    #(
      "history",
      projection_component_json(
        history_state,
        history_offset,
        history_lag,
        history_failure,
      ),
    ),
    #(
      "text",
      projection_component_json(text_state, text_offset, text_lag, text_failure),
    ),
    #(
      "vector_membership",
      projection_component_json(
        vector_state,
        vector_offset,
        vector_lag,
        vector_failure,
      ),
    ),
  ])
}

fn projection_component_json(
  state: String,
  offset: Int,
  lag: Int,
  failure: String,
) -> json.Json {
  json.object([
    #("state", json.string(state)),
    #("last_applied_offset", json.int(offset)),
    #("lag", json.int(lag)),
    #(
      "failure",
      json.nullable(
        case failure == "" {
          True -> option.None
          False -> option.Some(failure)
        },
        of: json.string,
      ),
    ),
  ])
}

fn vector_projection_status_json(
  status: vector_bridge.ProjectionStatus,
) -> json.Json {
  let vector_bridge.ProjectionStatus(offset, documents, health, generation, backend) =
    status
  json.object([
    #("last_applied_offset", json.int(offset)),
    #("documents", json.int(documents)),
    #("generation", json.int(generation)),
    #("backend", json.string(backend)),
    #("health", json.string(vector_projection_health_name(health))),
  ])
}

fn vector_projection_health_name(health: projection_index.Health) -> String {
  case health {
    projection_index.Building -> "building"
    projection_index.Rebuilding -> "rebuilding"
    projection_index.Queryable -> "queryable"
    projection_index.Degraded(_) -> "degraded"
    projection_index.Failed(_) -> "failed"
  }
}
