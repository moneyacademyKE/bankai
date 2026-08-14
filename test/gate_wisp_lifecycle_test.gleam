import bankai/daemon_store
import bankai/gate_wisp/store as lifecycle_store
import bankai/gates/facts
import bankai/gates/service as gates
import bankai/mnesia_store
import bankai/socket
import bankai/time
import bankai/types.{DefaultTask}
import bankai/wisps/service as wisps
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

const workspace = "/tmp/bankai_gate_wisp_lifecycle_test"

fn reset() -> Nil {
  let _ = simplifile.create_directory_all(workspace)
  let _ = simplifile.write("", to: workspace <> "/tasks.jsonl")
  let _ = simplifile.write("", to: workspace <> "/memories.jsonl")
  let _ = simplifile.write("", to: workspace <> "/archive.jsonl")
  let _ = mnesia_store.init(workspace)
  let _ = mnesia_store.reset_workspace_for_test(workspace)
  let _ = lifecycle_store.init(workspace)
  let _ = lifecycle_store.reset_workspace_for_test(workspace)
  let _ = facts.reset_for_test(workspace)
  Nil
}

fn id(value: json.Json) -> String {
  value
  |> json.to_string
  |> string.split("\"id\":\"")
  |> fn(parts) {
    case parts {
      [_, tail, ..] ->
        tail
        |> string.split("\"")
        |> fn(values) {
          case values {
            [found, ..] -> found
            _ -> ""
          }
        }
      _ -> ""
    }
  }
}

pub fn daemon_boot_initializes_lifecycle_tables_test() {
  let boot_workspace = "/tmp/bankai_gate_wisp_boot_test"
  let _ = simplifile.create_directory_all(boot_workspace)
  let _ = simplifile.write("", to: boot_workspace <> "/tasks.jsonl")
  let _ = simplifile.write("", to: boot_workspace <> "/memories.jsonl")
  should.be_ok(daemon_store.boot(boot_workspace)) |> should.equal(Nil)
  should.be_ok(lifecycle_store.gate_audits(boot_workspace, ""))
  |> should.equal([])
  should.be_ok(lifecycle_store.wisp_archives(boot_workspace, ""))
  |> should.equal([])
}

pub fn gate_list_check_dry_run_resolve_and_waiter_wakeup_test() {
  reset()
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "Approve deploy", [
        "--kind",
        "gate",
        "--label",
        "escalate:human-review",
      ]),
    )
  let gate_id = id(gate)
  let waiter = should.be_ok(daemon_store.create(workspace, "Deploy", []))
  let waiter_id = id(waiter)
  let _ =
    should.be_ok(
      daemon_store.add_dependency(workspace, waiter_id, gate_id, [
        "--type",
        "waits_for",
      ]),
    )

  let listed = should.be_ok(gates.list(workspace, ["--state", "pending"]))
  listed |> json.to_string |> string.contains(gate_id) |> should.be_true
  let checked = should.be_ok(gates.check(workspace, gate_id)) |> json.to_string
  checked |> string.contains("manual_resolution_required") |> should.be_true
  checked |> string.contains(waiter_id) |> should.be_true
  checked |> string.contains("\"ready_if_resolved\":true") |> should.be_true

  let dry =
    should.be_ok(
      gates.resolve(workspace, gate_id, ["--dry-run", "--reason", "approved"]),
    )
    |> json.to_string
  dry |> string.contains("\"would_change\":true") |> should.be_true
  should.be_ok(mnesia_store.get_current(workspace, gate_id)).gate_satisfied
  |> should.be_false

  let resolved =
    should.be_ok(
      gates.resolve(workspace, gate_id, [
        "--actor",
        "moe",
        "--reason",
        "approved",
      ]),
    )
    |> json.to_string
  resolved |> string.contains("\"resolved\":true") |> should.be_true
  should.be_ok(daemon_store.ready_tasks(workspace, []))
  |> json.to_string
  |> string.contains(waiter_id)
  |> should.be_true

  let shown = should.be_ok(gates.show(workspace, gate_id)) |> json.to_string
  shown |> string.contains("human-review") |> should.be_true
  shown |> string.contains("\"network_attempted\":false") |> should.be_true
  shown |> string.contains("approved") |> should.be_true
}

pub fn timer_gate_wakes_waiter_without_becoming_ready_work_test() {
  reset()
  let now = time.now()
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "Timer gate", [
        "--kind",
        "gate",
        "--due",
        int.to_string(now - 1),
      ]),
    )
  let gate_id = id(gate)
  let waiter = should.be_ok(daemon_store.create(workspace, "Timer waiter", []))
  let waiter_id = id(waiter)
  let _ =
    should.be_ok(
      daemon_store.add_dependency(workspace, waiter_id, gate_id, [
        "--type",
        "waits_for",
      ]),
    )

  let ready =
    should.be_ok(daemon_store.ready_tasks(workspace, [])) |> json.to_string
  ready
  |> string.contains("\"id\":\"" <> waiter_id <> "\"")
  |> should.be_true
  ready |> string.contains("\"id\":\"" <> gate_id <> "\"") |> should.be_false
  let claimed = should.be_ok(daemon_store.claim_next_ready(workspace, []))
  id(claimed) |> should.equal(waiter_id)
  should.be_ok(gates.check(workspace, gate_id))
  |> json.to_string
  |> string.contains("timer_due")
  |> should.be_true
}

pub fn lifecycle_reset_is_scoped_and_resets_durable_sequences_test() {
  reset()
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "Sequenced gate", ["--kind", "gate"]),
    )
  let gate_id = id(gate)
  let first =
    should.be_ok(gates.resolve(workspace, gate_id, [])) |> json.to_string
  first |> string.contains("\"audit_sequence\":1") |> should.be_true

  // Re-initialization models daemon restart: durable sequence metadata is reused.
  should.be_ok(lifecycle_store.init(workspace)) |> should.equal(Nil)
  let persisted_gate =
    should.be_ok(
      daemon_store.create(workspace, "Sequenced gate after init", [
        "--kind",
        "gate",
      ]),
    )
  should.be_ok(gates.resolve(workspace, id(persisted_gate), []))
  |> json.to_string
  |> string.contains("\"audit_sequence\":2")
  |> should.be_true

  should.be_ok(lifecycle_store.reset_workspace_for_test(workspace))
  |> should.equal(Nil)
  should.be_ok(lifecycle_store.gate_audits(workspace, gate_id))
  |> should.equal([])

  let next_gate =
    should.be_ok(
      daemon_store.create(workspace, "Sequenced gate after reset", [
        "--kind",
        "gate",
      ]),
    )
  let next_gate_id = id(next_gate)
  should.be_ok(gates.resolve(workspace, next_gate_id, []))
  |> json.to_string
  |> string.contains("\"audit_sequence\":1")
  |> should.be_true
}

pub fn audit_and_archive_queries_are_sequence_ordered_test() {
  reset()
  let first_gate =
    should.be_ok(
      daemon_store.create(workspace, "First audit gate", ["--kind", "gate"]),
    )
  let second_gate =
    should.be_ok(
      daemon_store.create(workspace, "Second audit gate", ["--kind", "gate"]),
    )
  let first_gate_id = id(first_gate)
  let second_gate_id = id(second_gate)
  let _ = should.be_ok(gates.resolve(workspace, second_gate_id, []))
  let _ = should.be_ok(gates.resolve(workspace, first_gate_id, []))
  should.be_ok(lifecycle_store.gate_audits(workspace, ""))
  |> list.map(fn(row) { row.sequence })
  |> should.equal([1, 2])

  let first_wisp =
    should.be_ok(
      daemon_store.create(workspace, "First archive wisp", ["--kind", "wisp"]),
    )
  let second_wisp =
    should.be_ok(
      daemon_store.create(workspace, "Second archive wisp", ["--kind", "wisp"]),
    )
  let first_wisp_id = id(first_wisp)
  let second_wisp_id = id(second_wisp)
  let _ = should.be_ok(wisps.burn(workspace, second_wisp_id, []))
  let _ = should.be_ok(wisps.burn(workspace, first_wisp_id, []))
  should.be_ok(lifecycle_store.wisp_archives(workspace, ""))
  |> list.map(fn(row) { row.sequence })
  |> should.equal([1, 2])
}

pub fn signed_fact_is_verified_before_persistence_and_revocation_closes_fact_gate_test() {
  reset()
  let signer = "/tmp/bankai_gate_wisp_fact_signer"
  let _ = facts.reset_for_test(signer)
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "External check", ["--kind", "gate"]),
    )
  let gate_id = id(gate)
  let waiter = should.be_ok(daemon_store.create(workspace, "Fact waiter", []))
  let waiter_id = id(waiter)
  let _ =
    should.be_ok(
      daemon_store.add_dependency(workspace, waiter_id, gate_id, [
        "--type",
        "waits_for",
      ]),
    )
  let issuer = should.be_ok(facts.public_key(signer))
  let _ = should.be_ok(facts.trust_issuer(workspace, issuer))
  let now = time.now()
  let wire =
    should.be_ok(facts.sign(
      signer,
      gate_id,
      facts.Satisfied,
      now,
      now + 10_000_000_000,
    ))
  let wire_json = facts.encode(wire)

  let ingested =
    should.be_ok(gates.ingest_fact(workspace, gate_id, issuer, wire_json))
    |> json.to_string
  ingested |> string.contains("\"verified\":true") |> should.be_true
  ingested |> string.contains("\"persisted\":true") |> should.be_true
  should.be_ok(lifecycle_store.valid_facts(workspace, gate_id, now + 1))
  |> list.length
  |> should.equal(1)

  should.be_ok(gates.ingest_fact(workspace, gate_id, issuer, wire_json))
  |> json.to_string
  |> string.contains("\"replay\":true")
  |> should.be_true
  should.be_ok(gates.check(workspace, gate_id))
  |> json.to_string
  |> string.contains("\"open\":true")
  |> should.be_true
  should.be_ok(daemon_store.ready_tasks(workspace, []))
  |> json.to_string
  |> string.contains(waiter_id)
  |> should.be_true
  let _ = should.be_ok(facts.revoke_issuer(workspace, issuer))
  should.be_ok(gates.check(workspace, gate_id))
  |> json.to_string
  |> string.contains("\"open\":false")
  |> should.be_true
  should.be_ok(daemon_store.ready_tasks(workspace, []))
  |> json.to_string
  |> string.contains(waiter_id)
  |> should.be_false
}

pub fn unverified_fact_never_persists_test() {
  reset()
  let signer = "/tmp/bankai_gate_wisp_untrusted_signer"
  let _ = facts.reset_for_test(signer)
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "External check", ["--kind", "gate"]),
    )
  let gate_id = id(gate)
  let issuer = should.be_ok(facts.public_key(signer))
  let now = time.now()
  let wire =
    should.be_ok(facts.sign(
      signer,
      gate_id,
      facts.Satisfied,
      now,
      now + 10_000_000_000,
    ))

  gates.ingest_fact(workspace, gate_id, issuer, facts.encode(wire))
  |> should.be_error
  should.be_ok(lifecycle_store.valid_facts(workspace, gate_id, now + 1))
  |> should.equal([])
}

pub fn wisp_ttl_filters_promote_digest_and_archive_first_burn_test() {
  reset()
  let now = time.now()
  let permanent =
    should.be_ok(
      daemon_store.create(workspace, "Permanent scratch", ["--kind", "wisp"]),
    )
  let permanent_id = id(permanent)
  let permanent_expiry =
    should.be_ok(lifecycle_store.wisp_expiry(workspace, permanent_id))
  permanent_expiry |> should.equal(option.None)
  let expired =
    should.be_ok(
      daemon_store.create(workspace, "Expired scratch", [
        "--kind",
        "wisp",
        "--expires-at",
        int.to_string(now - 1),
      ]),
    )
  let expired_id = id(expired)
  let active =
    should.be_ok(
      daemon_store.create(workspace, "Active scratch", [
        "--kind",
        "wisp",
        "--ttl",
        "3600",
      ]),
    )
  let active_id = id(active)

  let expired_list =
    should.be_ok(wisps.list(workspace, ["--state", "expired"]))
    |> json.to_string
  expired_list |> string.contains(expired_id) |> should.be_true
  expired_list |> string.contains(active_id) |> should.be_false
  expired_list |> string.contains(permanent_id) |> should.be_false
  should.be_ok(wisps.digest(workspace, active_id))
  |> json.to_string
  |> string.contains("source_history_preserved")
  |> should.be_true

  let promoted =
    should.be_ok(wisps.promote(workspace, active_id, ["--actor", "agent"]))
  promoted
  |> json.to_string
  |> string.contains("archive_sequence")
  |> should.be_true
  should.be_ok(mnesia_store.get_current(workspace, active_id)).kind
  |> should.equal(DefaultTask)

  let burned =
    should.be_ok(wisps.burn(workspace, expired_id, [])) |> json.to_string
  burned
  |> string.contains("\"archived_before_removal\":true")
  |> should.be_true
  mnesia_store.get_current(workspace, expired_id) |> should.be_error
  let archives =
    should.be_ok(lifecycle_store.wisp_archives(workspace, expired_id))
  list.length(archives) |> should.equal(1)
  let assert [archive] = archives
  archive.task_json |> string.contains("Expired scratch") |> should.be_true
}

pub fn wisp_gc_is_deterministic_and_compact_never_drops_local_wisps_test() {
  reset()
  let now = time.now()
  let first =
    should.be_ok(
      daemon_store.create(workspace, "First expired", [
        "--kind",
        "wisp",
        "--expires-at",
        int.to_string(now - 2),
      ]),
    )
  let second =
    should.be_ok(
      daemon_store.create(workspace, "Second expired", [
        "--kind",
        "wisp",
        "--expires-at",
        int.to_string(now - 1),
      ]),
    )
  let live =
    should.be_ok(
      daemon_store.create(workspace, "Local scratch", ["--kind", "wisp"]),
    )
  let first_id = id(first)
  let second_id = id(second)
  let live_id = id(live)

  let preview =
    should.be_ok(wisps.gc(workspace, ["--dry-run"])) |> json.to_string
  preview |> string.contains(first_id) |> should.be_true
  preview |> string.contains(second_id) |> should.be_true
  let _ = should.be_ok(wisps.gc(workspace, []))
  mnesia_store.get_current(workspace, first_id) |> should.be_error
  mnesia_store.get_current(workspace, second_id) |> should.be_error
  let all_archives = should.be_ok(lifecycle_store.wisp_archives(workspace, ""))
  list.map(all_archives, fn(row) { row.sequence }) |> should.equal([1, 2])

  let _ = should.be_ok(daemon_store.compact(workspace))
  should.be_ok(mnesia_store.get_current(workspace, live_id)).title
  |> should.equal("Local scratch")
}

pub fn socket_routes_are_data_shaped_test() {
  reset()
  let gate =
    should.be_ok(
      daemon_store.create(workspace, "Socket gate", ["--kind", "gate"]),
    )
  let gate_id = id(gate)
  case
    socket.handle_request(workspace, socket.Request("gate_check", [gate_id]))
  {
    socket.OkResponse(value) ->
      value |> string.contains("reasons") |> should.be_true
    socket.ErrorResponse(_) -> False |> should.be_true
  }
  case
    socket.handle_request(
      workspace,
      socket.Request("wisp_list", ["--state", "all"]),
    )
  {
    socket.OkResponse(_) -> True |> should.be_true
    socket.ErrorResponse(_) -> False |> should.be_true
  }
}
