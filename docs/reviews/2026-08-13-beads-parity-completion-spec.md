# Bankai–Beads Useful-Parity Completion Specification

> [!NOTE]
> **Implementation Complete (2026-08-14):** All 10 delivery items in Section 9 have been **fully implemented and verified** (246 passed tests, zero warnings). See ADR-0010, ADR-0011, ADR-0012, and the [Verified Parity Matrix](../../gap_analysis_bankai_vs_beads.md).

**Date:** 2026-08-13  
**Tracking:** [#6](https://github.com/moneyacademyKE/bankai/issues/6)  
**Pinned Bankai baseline:** `origin/main` at `a641b4fab9df17148b84b6c9581039f88d86245b`  
**Pinned Beads comparison:** `gastownhall/beads` at `60b15f2e6b678d4aea4aeea53e18ad506e7d4b22` / `v1.2.1`  
**Working branch:** `feat/beads-parity-completion`

## 1. Problem

Bankai already supports the core local agent-task loop and has stronger boundaries than Beads in several areas: immutable content-addressed history, daemon-owned task authority, signed snapshot exchange, authenticated local service capabilities, and fail-closed cluster admission. It is not yet useful-parity complete because several operations exist only as partial models, local WIP, or narrow command paths.

The first defect is semantic rather than cosmetic: the live daemon currently applies blocking-cycle validation to every relation type. Informational relations such as `relates_to` and `duplicates` must not be rejected because they close a path in the blocking DAG.

The target is **useful capability parity**, not command-count parity.

## 2. Target state

An agent using one stable CLI/socket/MCP contract can:

1. create, query, explain, claim, release, reopen, defer, undefer, label, and batch-mutate work atomically;
2. add, remove, filter, traverse, and export typed relationships without semantic drift;
3. register and locally approve pure content-addressed rules under explicit resource bounds;
4. instantiate reusable declarative workflow DAGs atomically and idempotently;
5. operate gates and local-only wisps through complete lifecycles;
6. catalog, validate, preview, restore, and reconcile backups safely;
7. inspect peers and conflicts without silent winner selection;
8. configure agent instructions/hooks non-destructively;
9. verify multi-node claims using live TLS/quorum/recovery evidence rather than architecture-shaped optimism.

## 3. Authority invariants

| Concern | Authority | Invariant |
|---|---|---|
| Tasks, rules, templates, gates, wisps | Bankai Mnesia behind daemon transactions | No CLI, projection, rule, or adapter writes domain truth directly. |
| History | Immutable content-addressed values | Mutation creates a new version; prior values are never overwritten. |
| Query/ranking/analytics | AaronDB projections | Derived state may lag or rebuild but never decides task truth. |
| Portability/federation | JSONL and signed snapshots | Exchange is explicit; it is neither a second live database nor consensus. |
| Mobile policy | Gleamunison source identity plus local approval | Arrival is not trust; rules receive immutable data and no ambient mutation capability. |
| External systems | Optional adapters producing authenticated facts | Credentials and provider network calls remain outside readiness policy and task truth. |

## 4. Accepted scope

### 4.1 Relation integrity and graph operations

- Apply cycle checks only to `blocks`, `waits_for`, and `conditional_blocks`.
- Add daemon/socket/MCP regression tests for valid non-blocking cycles.
- Add idempotent relation removal with explicit relation type.
- Add incoming/outgoing/both traversal with optional type filter and bounded depth.
- Add stable JSON graph export; Mermaid is a presentation adapter over the JSON contract.
- Add integrity output for missing targets, blocking cycles, duplicate edges, and invalid parent chains.

### 4.2 Mobile-rule productization

- Reconcile the existing durable artifact/approval/audit WIP with `origin/main` capability authentication.
- Keep registration, approval, evaluation, and audit as distinct operations.
- Keep immutable optional-task JSON as the only evaluator input.
- Retain source/name/time bounds and unlinked monitored worker isolation.
- Add `max_heap_size` and a reduction/call budget enforced by the evaluator boundary; budget exhaustion is an audited error.
- Never replicate approval implicitly.

### 4.3 Structured operational views

One pure `TaskViewSpec` owns filtering, sorting, offset, limit, and projection shape for:

- `list`;
- `ready`;
- `count`;
- `blocked`.

Supported fields: status, kind, priority range, assignee, labels-any/all, deferral, created/updated ranges, stable sort, offset, and limit. `ready --explain` returns data, not prose: active state, deferral, gate state, blocker relation/status/presence, claimability, and final readiness.

### 4.4 Lifecycle and atomic mutation primitives

- `release` clears assignee and returns in-progress work to open under explicit preconditions.
- `reopen` transitions completed/closed work to open and clears closure state.
- `undefer` clears `defer_until`.
- `label remove` is idempotent.
- Batch mutation validates every command and authorization decision before one transaction; one failure writes nothing.
- Idempotency keys prevent duplicate materialization on retry.

### 4.5 Declarative molecules

A molecule is immutable validated data, not executable policy.

Minimal model:

- template identity and schema version;
- named node specs containing title, description, kind, priority, labels, optional parent reference, and variable placeholders;
- typed edges between node names;
- declared variables with required/default values;
- provenance linking each instantiated task to template hash, instance id, and node name;
- instance status derived from instantiated tasks.

Instantiation rules:

1. decode and validate the complete template and bindings;
2. reject duplicate node names, unknown variables, unknown edge endpoints, invalid parent references, and blocking cycles before writes;
3. derive deterministic instance/task identities from template hash plus idempotency key/node name;
4. create tasks and relations in one Mnesia transaction;
5. a retry with the same idempotency key returns the same instance; conflicting bindings fail;
6. `progress` and `current` are views; `distill/squash` must never erase immutable source history.

### 4.6 Gates and wisps

Gates:

- list/show/check/resolve;
- dry-run explanation;
- waiters derived from incoming blocking relations;
- deterministic wake-up after resolution;
- escalation metadata only when a real workflow consumes it;
- external facts enter through signed, issuer-scoped, expiry-bearing adapter records.

Wisps:

- explicit list/filter;
- TTL and expiry state;
- promote to a normal task through a new immutable version;
- digest/squash as derived output;
- archive-first burn and explicit GC policy;
- remain excluded from portable exports and peer snapshots until promoted.

### 4.7 Backup, restore, federation, and journal

- Catalog backups by immutable manifest: schema, creation time, record counts, digest, source workspace, and current-head digest.
- Validate/dry-run before restore; report malformed, duplicate, stale, new, and divergent records.
- Restore through the same validated Mnesia import transaction; never copy live Mnesia files.
- Require explicit resolution for divergent heads; preserve both immutable versions and an audit record.
- Add peer list/show/check and conflict list/show/resolve UX.
- A public committed-change journal ships only as a bounded projection of the existing ordered change log with checkpoint, retention-floor, truncation-error, and tail-limit semantics. If no consumer exists, keep the contract documented and do not invent SSE/HTTP.

### 4.8 Setup, hooks, and optional adapters

- `setup list/check/preview/apply/remove`, project/global scope, and custom recipes.
- Bankai owns only marker-delimited sections; applying and removing never overwrite unrelated human guidance.
- Hook install/check/remove is idempotent and preserves existing hooks through composition.
- Worktree diagnostics report branch, common git dir, and per-worktree instruction/hook state; Bankai does not manage Git worktrees.
- Provider and embedding integrations are optional out-of-core adapters. Lexical retrieval remains the deterministic fallback.

### 4.9 Multi-host evidence

A production-HA statement requires live nodes—not a one-voter simulation—with:

- TLS-authenticated BEAM distribution;
- concurrent claim contention;
- leader/fence changes;
- quorum loss and mutation refusal;
- quorum restoration without double ownership;
- partition/rejoin behavior;
- projection rebuild after restart;
- sustained-load measurements and recorded SLOs.

If the environment cannot supply independent hosts/certificates/network control, the correct result is a durable blocked-evidence report and no HA claim.

## 5. Explicit exclusions

- Dolt or SQL as a second task authority.
- Raw SQL as public product semantics.
- Matching Beads' command count or aliases.
- Hidden provider/network reads during readiness.
- Bankai-owned Git worktree lifecycle.
- Arbitrary untyped metadata as a schema junk drawer.
- Legacy JSONL-as-replication-authority patterns.
- Automatically trusting remotely received rules or facts.

## 6. Compatibility and migration

- Persistent Task-field additions require a canonical version bump, safe legacy defaults, serde coverage, fixtures, import/export round trips, and content-hash validation.
- Prefer separate versioned Mnesia tables for template, rule, adapter-fact, backup-manifest, and idempotency domains rather than inflating `Task` with unrelated state.
- Every schema initializer is idempotent and upgrade-safe.
- Existing task hashes and immutable versions remain addressable.
- No migration rewrites historical task bytes in place.

## 7. Module-shape constraints

The current `daemon_store.gleam` (~1,571 LOC) and `cli.gleam` (~1,286 LOC) already violate the 500 LOC ceiling. New capability work must extract cohesive modules instead of extending either monolith:

- `task_query` / `readiness`;
- `task_lifecycle` / `task_batch`;
- `relations`;
- `molecules/{types,validate,store,service}`;
- `gates` and `wisps`;
- `backup/{manifest,validate,service}`;
- `setup/{recipe,service}`.

Thin daemon/socket/MCP dispatchers may wire these services but must not duplicate domain policy.

## 8. Red/green verification

| Layer | Required evidence |
|---|---|
| Pure policy | Relation blocking semantics, traversal bounds, task-view parsing/application, readiness explanations, molecule validation, gate/wisp state rules. |
| Mnesia transaction | No-write-on-failure, immutable history, idempotent retry, batch atomicity, restore round trip, divergence preservation. |
| Protocol | Equivalent CLI/socket/MCP results and capability authorization for every new operation. |
| Security | Rule denial/revocation, heap/reduction/time bounds, audit on success/failure, signed fact expiry/issuer rejection. |
| Distributed | Live TLS contention, partition, quorum-loss refusal, recovery, fencing, projection restart. |
| Release | `gleam format --check`, `gleam build`, `gleam test`, `git diff --check`, CI, updated capability matrix, verification witness. |

## 9. Delivery order

1. Preserve/reconcile worktree and capability-auth baseline.
2. Correct relation semantics and graph operations.
3. Finish resource-bounded mobile rules.
4. Wire task views and readiness explanations.
5. Complete lifecycle and atomic batch primitives.
6. Implement molecules.
7. Complete gates and wisps.
8. Complete backup/restore/conflict UX and conditional journal.
9. Complete setup/hooks and adapter seams.
10. Produce multi-host evidence, final verification witness, atomic commits, and a PR fixing #6.

## 10. Rich Hickey certification gate

This specification passes only if implementation preserves one authority per concern, represents workflows and explanations as data, validates before mutation, and refuses complexity that has no measured consumer. A wider command catalog with duplicated policy fails even if every command works.
