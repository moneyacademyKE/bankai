# Bankai-native parity verification witness

**Date:** 2026-08-08
**Scope:** Approved Bankai-native parity roadmap (Tasks 1–8)
**Verdict:** Pass for the local workflow release; federation and real embedding
providers remain intentionally unshipped.

## Evidence map

| Claim | Evidence |
|---|---|
| Daemon/Mnesia is the local write authority | ADR-0004; `src/bankai/mnesia_store.gleam`; `src/bankai/daemon_store.gleam`; `test/mnesia_store_test.gleam` |
| Old JSONL records remain importable | `test/fixtures/legacy-v2-tasks.jsonl`; `legacy_v2_fixture_bootstrap_export_restart_round_trip_test` |
| Current heads and immutable versions round-trip | `jsonl_export_import_round_trip_preserves_versions_and_heads_test`; export/backup/reconciliation tests |
| Task kinds, explicit parents, relation/readiness policy | `src/bankai/types.gleam`; `src/bankai/graph.gleam`; graph/daemon/MCP tests |
| Deferred work, explainable state, atomic claiming | `test/mnesia_store_test.gleam` readiness/defer/show regressions |
| Duplicate consolidation is transactional/idempotent | `duplicate_merge_rewrites_graph_is_idempotent_and_preserves_history_test` |
| Gates, local-only wisps, graph/doctor tooling | daemon/socket/MCP tests; `TaskKind.Gate` / `TaskKind.Wisp`; ADR-0005. Transactional molecules are **not** implemented. |
| Derived projection lifecycle decision | [Projection benchmark](projection-benchmark-2026-08-08.md) |
| Current reconciliation is not consensus | ADR-0006 |

## Migration rehearsal

The legacy fixture contains canonical pre-parity JSONL records without `kind`,
`parent_id`, `defer_until`, closure, or gate fields. The rehearsal performs:

1. legacy JSONL boot import into Mnesia;
2. validation that current heads and immutable versions retain both legacy task
   IDs/hashes;
3. defaulting of absent fields (`Task`, no parent, no defer);
4. deterministic Mnesia export back to JSONL;
5. a daemon restart that proves the bootstrap checkpoint does not duplicate
   immutable versions;
6. a read-only `doctor` health check.

This is deliberately not a fake binary downgrade test: ADR-0004 preserves the
original JSONL before Mnesia import, so rollback is performed by running the
previous JSONL-only binary against that untouched snapshot.

## Commands run

| Command | Result |
|---|---|
| `gleam format` | Pass |
| `gleam format --check` | Pass |
| `gleam build` | Pass; existing unrelated warnings remain |
| `gleam test` | **149 passed, 0 failures**; it intentionally logs one isolated mobile-rule crash report as part of a passing containment test |
| `git diff --check` | Pass |
| `bench/projection_bench.erl` twice | Pass; results recorded in the benchmark report |

The test run intentionally logs one BEAM crash report from the isolated mobile
rule crash-survival test. That test passes; the log is evidence that isolation
contains the crash, not a suite failure.

## Release limits

- Bankai has local Mnesia transactions, not cross-machine consensus.
  JSONL/peer exchange is snapshot reconciliation only; ADR-0006 specifies the
  still-unimplemented signed identity, causality, conflict, and recovery model.
- aarondb projections are derived and rebuildable. The generic incremental-cache
  proposal was rejected by measurement. The current per-command HNSW vector
  path is unsuitable for large boards and needs a separately bounded design.
- The default vector backend is deterministic **term-hash lexical** matching;
  it is not a real embedding provider and does not promise synonym recall.
- External PR/CI/remote gate adapters and vendor-coupled GitHub sync are not
  shipped. Local/manual/timer workflow primitives are the release scope.
- Existing unused-import/helper warnings are pre-existing cleanup items. They
  do not affect test success, but a warning-free release is a separate hygiene
  task.

## Rich Hickey check

The release keeps truth, derivation, and interchange separate: Mnesia is
truth, aarondb is derived retrieval, and JSONL is portable data. Federation is
explicitly deferred rather than smuggled in through a misleading word like
“sync.”
