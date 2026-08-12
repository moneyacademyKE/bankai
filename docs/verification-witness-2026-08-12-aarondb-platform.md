# Bankai AaronDB 4.2 Platform Verification Witness

**Date:** 2026-08-12
**Scope:** Bankai’s AaronDB 4.2 integration on the local working tree
**Verdict:** **Verified for the defined local and clustered-adapter contracts. Not a production multi-node HA certification.**

## Authority contract

| Mode | Command authority | Task materialization | Derived state | Admission / recovery contract |
|---|---|---|---|---|
| Local | One daemon with Bankai-owned Mnesia transactions | `bankai_current_v2` and immutable `bankai_versions_v2` | AaronDB durable-log/changefeed Datalog, BM25, and managed HNSW projections | No quorum claim; projection loss rebuilds from Mnesia snapshot plus ordered tail |
| Clustered adapter | AaronDB committed command / lease / fence admission | Each committed command applies once to Bankai Mnesia | Same replayable projections | Requires matching platform + cluster transport profiles; missing or invalid transport is `recovery-required` and clustered serving refuses to start |

**Non-negotiable distinction:** Mnesia is materialized task truth. AaronDB projections are never a task authority. JSONL is deliberate interchange and recovery input, never a live mutable store.

## Evidence executed

| Command | Result |
|---|---|
| `gleam format --check` | Pass |
| `gleam build` | Pass; pre-existing unused-import/helper warnings remain in unrelated legacy modules/tests |
| `gleam test` | **177 passed, 0 failures** |
| `git diff --check` | Pass |

The suite emits an expected BEAM crash report from `rules_test.run_isolated_survives_crash_test`; that test deliberately proves a crashing mobile rule cannot kill the rule registry.

## Safety scenarios exercised

| Scenario | Evidence | Outcome |
|---|---|---|
| Mnesia → JSONL export → clean Mnesia import | `platform_rehearsal_test.local_mnesia_export_rebootstrap_preserves_immutable_history_test` | Preserves two immutable versions and restores the completed current head |
| Local mode status | `platform_rehearsal_test.local_profile_remains_honest_without_cluster_claims_test` | Reports `local` / `healthy`; clustered claim API rejects local workspaces |
| Missing clustered transport config | `platform_rehearsal_test.clustered_profile_without_transport_refuses_recovery_and_mutation_admission_test` | Reports `recovery-required` through daemon/socket status |
| Profile/transport binding and identity policy | `cluster_transport_test` | Requires matching cluster/node, member certificate, issuer, bounded RPC size, reconnect budget, and timeout configuration |
| No quorum | `cluster_test.cluster_status_has_explicit_read_index_and_local_status_is_honest_test` | ReadIndex/status and new admissions reject once quorum is forced unavailable |
| Duplicate claim / stale fence | `cluster_test.cluster_leases_have_one_winner_are_idempotent_and_fence_stale_holders_test` | One holder wins; retries are idempotent; expired replacement raises fence; stale transition fails |
| Ordered change/replay/checkpoint | `mnesia_store_test` projection coverage | Projection bootstrap, tail replay, checkpoint, runtime loss, and vector exact-oracle equivalence remain covered |
| Partition/crash/reorder/slow follower/membership/clock schedules | `platform_rehearsal_test.distributed_harness_schedules_preserve_claim_safety_invariants_test` | AaronDB harness detects split brain, duplicate application, stale fences, and missing recovery alarms deterministically |

## Operators’ status surface

- `bankai doctor` returns task integrity plus `mode`, AaronDB projection/index health and offsets, cluster quorum/leader/lease status, transport state, and `healthy` / `degraded` / `recovery-required` verdict.
- `bankai cluster-status` returns the cluster, transport, and recovery records.
- MCP exposes `doctor`, `cluster_status`, and `platform_status`; all are daemon-only and preserve Bankai JSON/MCP envelopes.
- Clustered `bankai serve` requires both `.bankai/bankai-platform.json` and `.bankai/cluster-transport.json`. It does not silently fall back to an independent local writer.

## Residual risks and honest limits

1. **No multi-host production evidence yet.** Current clustered tests use deterministic one-voter rehearsal and library-level distributed-harness schedules. A real HA claim requires live authenticated BEAM-distribution nodes, actual quorum loss/recovery drills, membership-change operations, persistence validation, and operational SLOs.
2. **Transport config is admission policy, not automatic TLS provisioning.** Operators configure TLS BEAM distribution; Bankai verifies the profile and identity facts it is given.
3. **Managed HNSW is daemon-local and rebuildable.** It is not persistent across daemon restart, and its term-hash vectors are lexical—not semantic embeddings.
4. **Signed replica snapshots are replication, not coordinated task ownership.** Use clustered commands for fenced claim coordination; snapshot exchange preserves/reports conflicts rather than choosing a remote head silently.
5. **Remote provider gates and molecule/templates remain deliberately unimplemented.**

## Rich Hickey certification

The integration maintains the essential distinctions: task truth versus derived views; snapshot replication versus coordination; identity admission versus authorization; and a configured transport policy versus a proof of HA. It adds no second task authority and fails closed at the cluster boundary.
