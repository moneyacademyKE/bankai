import aarondb/projection_index
import bankai/daemon_store
import bankai/mnesia_store
import bankai/projections
import bankai/socket
import bankai/storage/store
import bankai/sync/jsonl
import bankai/time
import bankai/types
import bankai/vector_bridge
import gleam/int
import gleam/json
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gleeunit/should
import simplifile

pub fn main() {
  gleeunit.main()
}

const workspace = "/tmp/bankai_mnesia_store_test"

fn wipe() {
  let _ = simplifile.create_directory_all(workspace)
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  let _ = simplifile.write("", to: workspace <> "/roundtrip.jsonl")
  Nil
}

fn reset_workspace(ws: String) -> Nil {
  let _ = simplifile.create_directory_all(ws)
  let _ = mnesia_store.init(ws)
  let _ = mnesia_store.reset_workspace_for_test(ws)
  let _ = simplifile.write("", to: ws <> "/tasks.jsonl")
  Nil
}

fn task_id(response: Result(json.Json, String)) -> String {
  case response {
    Ok(value) -> json.to_string(value)
    Error(_) -> ""
  }
}

pub fn legacy_jsonl_imports_once_and_preserves_history_test() {
  wipe()
  let _ = jsonl.flush([], to: workspace <> "/tasks.jsonl")
  let _ = daemon_store.boot(workspace)
  let created = daemon_store.create(workspace, "Persistent task", [])
  let rendered = task_id(created)
  rendered |> string.contains("Persistent task") |> should.be_true

  let current = should.be_ok(mnesia_store.current_store(workspace))
  store.current_tasks(current)
  |> list.length
  |> should.equal(1)

  let versions = should.be_ok(mnesia_store.version_store(workspace))
  store.list(versions)
  |> list.length
  |> should.equal(1)
}

pub fn export_and_backup_are_mnesia_snapshots_test() {
  wipe()
  let _ = daemon_store.boot(workspace)
  let _ = daemon_store.create(workspace, "Snapshot task", [])
  let exported = should.be_ok(daemon_store.export_jsonl(workspace))
  json.to_string(exported)
  |> string.contains("exported immutable task history")
  |> should.be_true
  let on_disk = should.be_ok(jsonl.load(from: workspace <> "/tasks.jsonl"))
  on_disk |> list.length |> fn(length) { length > 0 } |> should.be_true

  let backed_up = should.be_ok(daemon_store.backup_jsonl(workspace))
  json.to_string(backed_up)
  |> string.contains("backed up Mnesia history")
  |> should.be_true
}

pub fn jsonl_export_import_round_trip_preserves_versions_and_heads_test() {
  wipe()
  let _ = daemon_store.boot(workspace)
  let created = should.be_ok(daemon_store.create(workspace, "Round trip", []))
  let raw = json.to_string(created)
  let id = case string.split(raw, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [found, ..] -> found
        [] -> ""
      }
    _ -> ""
  }
  let _ = should.be_ok(daemon_store.update(workspace, id, "completed"))
  let path = workspace <> "/roundtrip.jsonl"
  let _ = should.be_ok(daemon_store.export_jsonl_to(workspace, path))

  let imported_workspace = "/tmp/bankai_mnesia_roundtrip_import"
  let _ = simplifile.create_directory_all(imported_workspace)
  let _ = simplifile.write("", to: imported_workspace <> "/tasks.jsonl")
  let _ = daemon_store.boot(imported_workspace)
  let _ = should.be_ok(daemon_store.import_jsonl(imported_workspace, path))

  let versions = should.be_ok(mnesia_store.version_store(imported_workspace))
  store.list(versions)
  |> list.length
  |> fn(count) { count >= 2 }
  |> should.be_true
  let current = should.be_ok(mnesia_store.get_current(imported_workspace, id))
  current.status |> should.equal(types.Completed)
}

pub fn committed_changes_are_ordered_snapshot_safe_and_idempotent_test() {
  let ws = "/tmp/bankai_changefeed_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let initial = should.be_ok(mnesia_store.projection_snapshot(ws))
  initial |> string.contains("\"offset\":-1") |> should.be_true

  let first = should.be_ok(daemon_store.create(ws, "First event", []))
  let second = should.be_ok(daemon_store.create(ws, "Second event", []))
  let first_id = id_from_json(json.to_string(first))
  let second_id = id_from_json(json.to_string(second))
  let snapshot = should.be_ok(mnesia_store.projection_snapshot(ws))
  snapshot |> string.contains(first_id) |> should.be_true
  snapshot |> string.contains(second_id) |> should.be_true
  snapshot |> string.contains("\"offset\":1") |> should.be_true

  let events = should.be_ok(mnesia_store.change_tail(ws, -1))
  events |> list.length |> should.equal(2)
  let joined = string.join(events, "\n")
  joined |> string.contains("\"offset\":0") |> should.be_true
  joined |> string.contains("\"offset\":1") |> should.be_true
  joined |> string.contains("\"operation\":\"create\"") |> should.be_true
  let no_tail = should.be_ok(mnesia_store.change_tail(ws, 1))
  no_tail |> list.length |> should.equal(0)

  let _ = should.be_ok(daemon_store.update(ws, first_id, "completed"))
  let updated_events = should.be_ok(mnesia_store.change_tail(ws, 1))
  updated_events |> list.length |> should.equal(1)
  let replayed_events = should.be_ok(mnesia_store.change_tail(ws, 1))
  replayed_events |> should.equal(updated_events)
}

pub fn failed_transaction_leaves_no_change_event_test() {
  let ws = "/tmp/bankai_changefeed_failure_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let created = should.be_ok(daemon_store.create(ws, "CAS subject", []))
  let id = id_from_json(json.to_string(created))
  let after_create = should.be_ok(mnesia_store.change_tail(ws, -1))
  after_create |> list.length |> should.equal(1)

  let _ = should.be_error(daemon_store.update(ws, "missing", "completed"))
  let after_missing = should.be_ok(mnesia_store.change_tail(ws, -1))
  after_missing |> should.equal(after_create)

  let _ = should.be_ok(daemon_store.update(ws, id, "completed"))
  let after_update = should.be_ok(mnesia_store.change_tail(ws, -1))
  after_update |> list.length |> should.equal(2)
}

pub fn aarondb_projection_bootstrap_replay_and_checkpoint_test() {
  let ws = "/tmp/bankai_aarondb_projection_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let _ = should.be_ok(daemon_store.create(ws, "Projected first", []))
  let booted = should.be_ok(projections.bootstrap(ws))
  projections.healthy(booted) |> should.be_true
  let checkpoint =
    should.be_ok(mnesia_store.projection_checkpoint(ws, "bankai-history"))
  checkpoint |> should.equal(0)

  let _ = should.be_ok(daemon_store.create(ws, "Projected second", []))
  let replayed = should.be_ok(projections.catch_up(booted, ws))
  projections.healthy(replayed) |> should.be_true
  let pulled = should.be_ok(projections.pull(replayed, 0, 8))
  pulled |> list.length |> should.equal(1)
  let checkpoint_after =
    should.be_ok(mnesia_store.projection_checkpoint(
      ws,
      "bankai-vector-membership",
    ))
  checkpoint_after |> should.equal(1)

  // A restart rebuilds from Mnesia's snapshot + tail, not the old VM index.
  let restarted = should.be_ok(projections.bootstrap(ws))
  projections.healthy(restarted) |> should.be_true
  let restarted_tail = should.be_ok(projections.pull(restarted, 0, 8))
  restarted_tail |> list.length |> should.equal(1)

  let doctor = should.be_ok(daemon_store.doctor(ws))
  json.to_string(doctor)
  |> string.contains("\"changefeed\":{\"healthy\":true")
  |> should.be_true

  // Repeating the tail after its checkpoint produces no new derived entries.
  let replayed_again = should.be_ok(projections.catch_up(replayed, ws))
  projections.healthy(replayed_again) |> should.be_true
  let empty = should.be_ok(projections.pull(replayed_again, 1, 8))
  empty |> list.length |> should.equal(0)
}

pub fn contested_claim_allows_exactly_one_winner_test() {
  wipe()
  let _ = daemon_store.boot(workspace)
  let created = should.be_ok(daemon_store.create(workspace, "Claim once", []))
  let raw = json.to_string(created)
  let id = case string.split(raw, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [found, ..] -> found
        [] -> ""
      }
    _ -> ""
  }
  let first = daemon_store.claim(workspace, id, ["alice"])
  let second = daemon_store.claim(workspace, id, ["bob"])
  case first, second {
    Ok(_), Error(message) ->
      message |> string.contains("not open") |> should.be_true
    Error(message), Ok(_) ->
      message |> string.contains("not open") |> should.be_true
    _, _ -> should.be_true(False)
  }
}

pub fn derived_reads_use_unexported_mnesia_state_test() {
  let ws = "/tmp/bankai_mnesia_derived_reads_test"
  reset_workspace(ws)
  let _ = simplifile.write("", to: ws <> "/memories.jsonl")
  let _ = should.be_ok(daemon_store.boot(ws))
  let created =
    should.be_ok(daemon_store.create(ws, "Searchable live task", []))
  let raw = json.to_string(created)
  let id = case string.split(raw, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [found, ..] -> found
        [] -> ""
      }
    _ -> ""
  }

  let shown = should.be_ok(daemon_store.show_task(ws, id))
  json.to_string(shown)
  |> string.contains("Searchable live task")
  |> should.be_true
  let counted = should.be_ok(daemon_store.count_tasks(ws, []))
  json.to_string(counted) |> string.contains("\"count\":1") |> should.be_true
  let searched = should.be_ok(daemon_store.search(ws, ["Searchable"]))
  json.to_string(searched) |> string.contains(id) |> should.be_true
  let semantic = should.be_ok(daemon_store.semantic_duplicates(ws, []))
  json.to_string(semantic) |> string.contains("[]") |> should.be_true
  let prompt = should.be_ok(daemon_store.prime_query(ws, "Searchable"))
  json.to_string(prompt)
  |> string.contains("Semantic context")
  |> should.be_true

  let old_hash = case string.split(raw, "\"content_hash\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [found, ..] -> found
        [] -> ""
      }
    _ -> ""
  }
  let _ = should.be_ok(daemon_store.update(ws, id, "completed"))
  let history = should.be_ok(daemon_store.history(ws, id))
  json.to_string(history) |> string.contains("completed") |> should.be_true
  let inspected = should.be_ok(daemon_store.inspect(ws, old_hash))
  json.to_string(inspected)
  |> string.contains("Searchable live task")
  |> should.be_true
}

pub fn socket_reads_transactional_state_without_jsonl_export_test() {
  let read_workspace = "/tmp/bankai_mnesia_read_boundary_test"
  reset_workspace(read_workspace)
  let _ = daemon_store.boot(read_workspace)
  let created =
    should.be_ok(daemon_store.create(read_workspace, "Live daemon task", []))
  let raw = json.to_string(created)
  let id = case string.split(raw, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [found, ..] -> found
        [] -> ""
      }
    _ -> ""
  }

  let listed = should.be_ok(daemon_store.list_tasks(read_workspace, []))
  json.to_string(listed)
  |> string.contains("Live daemon task")
  |> should.be_true

  let ready = should.be_ok(daemon_store.ready_tasks(read_workspace, []))
  json.to_string(ready)
  |> string.contains("Live daemon task")
  |> should.be_true

  let _ = should.be_ok(daemon_store.update(read_workspace, id, "completed"))
  let ready_after_update =
    should.be_ok(daemon_store.ready_tasks(read_workspace, []))
  json.to_string(ready_after_update)
  |> string.contains("Live daemon task")
  |> should.be_false
}

pub fn ready_claim_is_atomic_and_respects_label_and_blocks_test() {
  let ws = "/tmp/bankai_ready_claim_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let _first =
    should.be_ok(daemon_store.create(ws, "First ready", ["--label", "api"]))

  let _ =
    should.be_ok(daemon_store.create(ws, "Second ready", ["--label", "api"]))
  let blocker = should.be_ok(daemon_store.create(ws, "Blocker", []))
  let blocked =
    should.be_ok(daemon_store.create(ws, "Blocked", ["--label", "api"]))
  let blocker_id = id_from_json(json.to_string(blocker))
  let blocked_id = id_from_json(json.to_string(blocked))
  let _ =
    should.be_ok(daemon_store.add_dependency(ws, blocked_id, blocker_id, []))

  let claimed =
    should.be_ok(daemon_store.claim_next_ready(ws, ["--label", "api", "alice"]))
  json.to_string(claimed) |> string.contains("alice") |> should.be_true

  let second_claim =
    daemon_store.claim_next_ready(ws, ["--label", "api", "bob"])
  case second_claim {
    Ok(value) ->
      json.to_string(value) |> string.contains(blocked_id) |> should.be_false
    Error(_) -> should.be_true(True)
  }

  let socket_claim =
    socket.handle_request(
      ws,
      socket.Request("ready", ["--claim", "carol", "--label", "api"]),
    )
  case socket_claim {
    socket.OkResponse(value) ->
      value |> string.contains(blocked_id) |> should.be_false
    socket.ErrorResponse(_) -> should.be_true(True)
  }
}

pub fn daemon_projection_runtime_reuses_view_and_advances_in_offset_order_test() {
  let ws = "/tmp/bankai_daemon_projection_runtime_test"
  reset_workspace(ws)
  let _ = should.be_ok(projections.reset_runtime_for_test(ws))
  let _ = should.be_ok(daemon_store.boot(ws))

  let started = should.be_ok(projections.runtime_status(ws))
  let projections.RuntimeStatus(
    healthy,
    watermark,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
  ) = started
  healthy |> should.be_true
  watermark |> should.equal(-1)

  let first = should.be_ok(daemon_store.create(ws, "Runtime first", []))
  let first_id = id_from_json(json.to_string(first))
  let search_after_first = should.be_ok(daemon_store.search(ws, ["Runtime"]))
  json.to_string(search_after_first)
  |> string.contains(first_id)
  |> should.be_true
  let after_first = should.be_ok(projections.runtime_status(ws))
  let projections.RuntimeStatus(
    _,
    first_watermark,
    _,
    history_offset,
    history_lag,
    _,
    _,
    text_offset,
    text_lag,
    _,
    _,
    vector_offset,
    vector_lag,
    _,
  ) = after_first
  first_watermark |> should.equal(0)
  history_offset |> should.equal(0)
  text_offset |> should.equal(0)
  vector_offset |> should.equal(0)
  history_lag |> should.equal(0)
  text_lag |> should.equal(0)
  vector_lag |> should.equal(0)

  let second = should.be_ok(daemon_store.create(ws, "Runtime second", []))
  let second_id = id_from_json(json.to_string(second))
  let search_after_second = should.be_ok(daemon_store.search(ws, ["second"]))
  json.to_string(search_after_second)
  |> string.contains(second_id)
  |> should.be_true
  let after_second = should.be_ok(projections.runtime_status(ws))
  let projections.RuntimeStatus(
    _,
    second_watermark,
    _,
    second_history_offset,
    _,
    _,
    _,
    second_text_offset,
    _,
    _,
    _,
    second_vector_offset,
    _,
    _,
  ) = after_second
  second_watermark |> should.equal(1)
  second_history_offset |> should.equal(1)
  second_text_offset |> should.equal(1)
  second_vector_offset |> should.equal(1)

  let doctor = should.be_ok(daemon_store.doctor(ws))
  json.to_string(doctor)
  |> string.contains("\"mode\":\"daemon-runtime\"")
  |> should.be_true
  json.to_string(doctor)
  |> string.contains("\"last_applied_offset\":1")
  |> should.be_true
}

pub fn projection_runtime_recovers_from_process_loss_by_rebuilding_mnesia_test() {
  let ws = "/tmp/bankai_daemon_projection_runtime_recovery_test"
  reset_workspace(ws)
  let _ = should.be_ok(projections.reset_runtime_for_test(ws))
  let _ = should.be_ok(daemon_store.boot(ws))
  let created =
    should.be_ok(daemon_store.create(ws, "Recoverable projection", []))
  let id = id_from_json(json.to_string(created))
  let _ = should.be_ok(daemon_store.search(ws, ["Recoverable"]))
  let _ = should.be_ok(projections.reset_runtime_for_test(ws))

  let rebuilt = should.be_ok(daemon_store.search(ws, ["Recoverable"]))
  json.to_string(rebuilt) |> string.contains(id) |> should.be_true
  let status = should.be_ok(projections.runtime_status(ws))
  let projections.RuntimeStatus(
    healthy,
    watermark,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
    _,
  ) = status
  healthy |> should.be_true
  watermark |> should.equal(0)
}

pub fn managed_vector_projection_reuses_generation_and_matches_exact_oracle_test() {
  let ws = "/tmp/bankai_managed_vector_projection_test"
  reset_workspace(ws)
  let _ = should.be_ok(vector_bridge.reset_projection_for_test(ws))
  let _ = should.be_ok(daemon_store.boot(ws))
  let first = should.be_ok(daemon_store.create(ws, "Authentication token", []))
  let second = should.be_ok(daemon_store.create(ws, "Authentication guide", []))
  let first_id = id_from_json(json.to_string(first))
  let second_id = id_from_json(json.to_string(second))

  let semantic =
    should.be_ok(daemon_store.semantic_duplicates(ws, ["--threshold", "0.0"]))
  json.to_string(semantic) |> string.contains(first_id) |> should.be_true
  let status = should.be_ok(vector_bridge.projection_status(ws))
  let vector_bridge.ProjectionStatus(
    offset,
    documents,
    health,
    _initial_generation,
    _backend,
  ) = status
  offset |> should.equal(1)
  documents |> should.equal(2)
  health |> should.equal(projection_index.Queryable)

  let task_docs = [
    vector_bridge.Document("task", first_id, "Authentication token"),
    vector_bridge.Document("task", second_id, "Authentication guide"),
  ]
  let approximate =
    should.be_ok(vector_bridge.projected_search(
      ws,
      offset,
      task_docs,
      "Authentication",
      0.0,
      2,
    ))
  let exact =
    should.be_ok(vector_bridge.projected_exact_search(
      ws,
      offset,
      task_docs,
      "Authentication",
      0.0,
      2,
    ))
  approximate |> should.equal(exact)

  let after_exact = should.be_ok(vector_bridge.projection_status(ws))
  let vector_bridge.ProjectionStatus(_, _, _, exact_generation, _) = after_exact

  let repeat = should.be_ok(vector_bridge.projection_status(ws))
  let vector_bridge.ProjectionStatus(_, _, _, repeated_generation, _) = repeat
  repeated_generation |> should.equal(exact_generation)

  let _ = should.be_ok(daemon_store.create(ws, "Authentication rollout", []))
  let _ =
    should.be_ok(daemon_store.semantic_duplicates(ws, ["--threshold", "0.0"]))
  let advanced = should.be_ok(vector_bridge.projection_status(ws))
  let vector_bridge.ProjectionStatus(
    advanced_offset,
    advanced_docs,
    _,
    advanced_generation,
    _backend,
  ) = advanced
  advanced_offset |> should.equal(2)
  advanced_docs |> should.equal(3)
  advanced_generation
  |> fn(value) { value > exact_generation }
  |> should.be_true

  let doctor = should.be_ok(daemon_store.doctor(ws))
  json.to_string(doctor)
  |> string.contains("\"vector_index\":{")
  |> should.be_true
  json.to_string(doctor)
  |> string.contains("\"health\":\"queryable\"")
  |> should.be_true
}

fn id_from_json(raw: String) -> String {
  case string.split(raw, "\"id\":\"") {
    [_, rest, ..] ->
      case string.split(rest, "\"") {
        [id, ..] -> id
        [] -> ""
      }
    _ -> ""
  }
}

pub fn defer_close_and_show_are_transactional_and_explainable_test() {
  let ws = "/tmp/bankai_workflow_controls_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let created = should.be_ok(daemon_store.create(ws, "Deferred work", []))
  let id = id_from_json(json.to_string(created))
  let future = time.now() + 86_400 * 1_000_000_000
  let _ = should.be_ok(daemon_store.defer_until(ws, id, int.to_string(future)))

  let ready = should.be_ok(daemon_store.ready_tasks(ws, []))
  json.to_string(ready) |> string.contains(id) |> should.be_false

  let shown = should.be_ok(daemon_store.show_task(ws, id))
  json.to_string(shown)
  |> string.contains("\"deferred\":true")
  |> should.be_true
  json.to_string(shown) |> string.contains("\"task\"") |> should.be_true
  json.to_string(shown) |> string.contains("\"blocking\"") |> should.be_true

  let closed = should.be_ok(daemon_store.close(ws, id, "superseded"))
  json.to_string(closed) |> string.contains("superseded") |> should.be_true
  let history = should.be_ok(daemon_store.history(ws, id))
  json.to_string(history) |> string.contains("closed") |> should.be_true

  let socket_defer =
    socket.handle_request(
      ws,
      socket.Request("update", [id, "--defer-until", int.to_string(future)]),
    )
  case socket_defer {
    socket.OkResponse(_) -> should.be_true(True)
    socket.ErrorResponse(_) -> should.be_true(False)
  }
}

pub fn doctor_and_dependency_graph_are_read_only_and_daemon_routable_test() {
  let ws = "/tmp/bankai_doctor_graph_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let blocker = should.be_ok(daemon_store.create(ws, "Blocker", []))
  let dependent = should.be_ok(daemon_store.create(ws, "Dependent", []))
  let blocker_id = id_from_json(json.to_string(blocker))
  let dependent_id = id_from_json(json.to_string(dependent))
  let _ =
    should.be_ok(
      daemon_store.add_dependency(ws, dependent_id, blocker_id, [
        "--type",
        "waits_for",
      ]),
    )

  let doctor = should.be_ok(daemon_store.doctor(ws))
  json.to_string(doctor)
  |> string.contains("\"healthy\":true")
  |> should.be_true
  json.to_string(doctor) |> string.contains("read-only") |> should.be_true

  let listed = should.be_ok(daemon_store.dependency_list(ws, dependent_id))
  json.to_string(listed) |> string.contains("waits_for") |> should.be_true
  let tree = should.be_ok(daemon_store.dependency_tree(ws, dependent_id))
  json.to_string(tree) |> string.contains(blocker_id) |> should.be_true

  let socket_doctor = socket.handle_request(ws, socket.Request("doctor", []))
  case socket_doctor {
    socket.OkResponse(value) ->
      value |> string.contains("healthy") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
  let socket_tree =
    socket.handle_request(ws, socket.Request("dep_tree", [dependent_id]))
  case socket_tree {
    socket.OkResponse(value) ->
      value |> string.contains(blocker_id) |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
}

pub fn duplicate_merge_rewrites_graph_is_idempotent_and_preserves_history_test() {
  let ws = "/tmp/bankai_duplicate_merge_test"
  reset_workspace(ws)
  let _ = should.be_ok(daemon_store.boot(ws))
  let canonical = should.be_ok(daemon_store.create(ws, "Canonical", []))
  let duplicate = should.be_ok(daemon_store.create(ws, "Duplicate", []))
  let dependent = should.be_ok(daemon_store.create(ws, "Dependent", []))
  let canonical_id = id_from_json(json.to_string(canonical))
  let duplicate_id = id_from_json(json.to_string(duplicate))
  let dependent_id = id_from_json(json.to_string(dependent))
  let _ =
    should.be_ok(
      daemon_store.add_dependency(ws, dependent_id, duplicate_id, []),
    )

  let merged =
    should.be_ok(daemon_store.merge_duplicate(ws, duplicate_id, canonical_id))
  json.to_string(merged)
  |> string.contains("\"idempotent\":false")
  |> should.be_true
  let source = should.be_ok(mnesia_store.get_current(ws, duplicate_id))
  source.status |> should.equal(types.Closed)
  source.closure_reason
  |> should.equal(option.Some("merged into " <> canonical_id))
  let rewritten = should.be_ok(mnesia_store.get_current(ws, dependent_id))
  rewritten.relationships
  |> list.any(fn(relation) { relation.target_id == canonical_id })
  |> should.be_true
  let source_history = should.be_ok(daemon_store.history(ws, duplicate_id))
  json.to_string(source_history) |> string.contains("closed") |> should.be_true

  let replay =
    should.be_ok(daemon_store.merge_duplicate(ws, duplicate_id, canonical_id))
  json.to_string(replay)
  |> string.contains("\"idempotent\":true")
  |> should.be_true
  let socket_merge =
    socket.handle_request(
      ws,
      socket.Request("merge", [duplicate_id, canonical_id]),
    )
  case socket_merge {
    socket.OkResponse(value) ->
      value |> string.contains("idempotent") |> should.be_true
    socket.ErrorResponse(_) -> should.be_true(False)
  }
}

/// Release rehearsal: v2 JSONL has no kind/parent/defer/gate fields. The daemon
/// must import it once, preserve its historical hashes, export it deterministically,
/// and expose the migrated defaults after a second boot.
pub fn legacy_v2_fixture_bootstrap_export_restart_round_trip_test() {
  let ws = "/tmp/bankai_legacy_v2_rehearsal"
  reset_workspace(ws)
  let fixture =
    should.be_ok(simplifile.read(from: "test/fixtures/legacy-v2-tasks.jsonl"))
  let _ = should.be_ok(simplifile.write(fixture, to: ws <> "/tasks.jsonl"))

  let _ = should.be_ok(daemon_store.boot(ws))
  let current = should.be_ok(mnesia_store.current_store(ws))
  store.current_tasks(current) |> list.length |> should.equal(2)
  let parent = should.be_ok(mnesia_store.get_current(ws, "bk-legacy-a"))
  parent.kind |> should.equal(types.DefaultTask)
  parent.parent_id |> should.equal(option.None)
  parent.defer_until |> should.equal(option.None)

  let versions_before = should.be_ok(mnesia_store.version_store(ws))
  store.list(versions_before) |> list.length |> should.equal(2)
  let _ = should.be_ok(daemon_store.export_jsonl(ws))
  let exported = should.be_ok(jsonl.load(from: ws <> "/tasks.jsonl"))
  exported |> list.length |> should.equal(2)
  let exported_parent =
    exported
    |> list.filter(fn(task) { task.id == "bk-legacy-a" })
    |> list.first
  case exported_parent {
    Ok(task) -> task.kind |> should.equal(types.DefaultTask)
    Error(_) -> should.be_true(False)
  }

  // A second boot consumes the metadata checkpoint rather than duplicating
  // immutable versions from the exported snapshot.
  let _ = should.be_ok(daemon_store.boot(ws))
  let versions_after = should.be_ok(mnesia_store.version_store(ws))
  store.list(versions_after) |> list.length |> should.equal(2)
  let doctor = should.be_ok(daemon_store.doctor(ws))
  json.to_string(doctor)
  |> string.contains("\"healthy\":true")
  |> should.be_true
}
