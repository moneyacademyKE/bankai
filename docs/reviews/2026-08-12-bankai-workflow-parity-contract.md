# Bankai Workflow Parity Contract

**Date:** 2026-08-12  
**Baseline:** `04ae8c8019428e8c6e98f8662036730df55f36fc` (`feat: adopt aarondb 4.2 platform integration`)  
**Tracking:** GitHub issue [#6](https://github.com/moneyacademyKE/bankai/issues/6)  
**Purpose:** This is the executable, current-state contract for closing the workflow gaps identified in the Beads/Bankai/Gleamunison review. It is a capability statement, not a marketing roadmap.

## Authority invariants

| Concern | Owner | Non-negotiable rule |
|---|---|---|
| Task, rule, and template truth | Bankai-owned Mnesia behind the daemon | Only the daemon transaction path may change durable domain truth. |
| History | Immutable content-addressed versions | A new state creates a new version; prior versions are never overwritten. |
| Retrieval, ranking, analytics | AaronDB projections | Projection loss or lag cannot block or redefine task truth. |
| Portability and reconciliation | JSONL and signed snapshots | Exchange is not a second live store and is not consensus. |
| Mobile policy | Gleamunison identity and pure evaluator | Source identity is distinct from local execution approval; rules receive no ambient authority. |

## Capability status

| Capability | Status at baseline | Final status (2026-08-14) | Acceptance evidence |
|---|---|---|---|
| Durable task state, immutable history, local atomic claim | **Shipped** | **Shipped** | Mnesia transaction, daemon/socket/MCP regression tests; ADR-0004 |
| Typed tasks, parents, typed dependencies, deferral, duplicate merge | **Shipped** | **Shipped** | Graph/cycle/CAS tests, bidirectional traversal, integrity audit; ADR-0005 |
| AaronDB Datalog, BM25, managed HNSW projections | **Shipped** | **Shipped** | Snapshot-plus-tail replay and health tests; ADR-0007 |
| Signed snapshots and clustered admission adapter | **Partial** | **Shipped & Evidenced** | Multi-node quorum/fence witness; ADR-0008, ADR-0011 |
| Gleamunison mobile rules | **Shipped locally** | **Shipped** | Durable source, local approval, audit, bounded worker, CLI/socket/MCP; ADR-0003, ADR-0009 |
| Structured task filtering and `ready --explain` | **Missing** | **Shipped** | Pure `task_view` spec with status/kind/priority/label/assignee filters and readiness rationale; ADR-0010 |
| Typed graph removal, direction-aware traversal/export | **Partial** | **Shipped** | In/out/both traversal, bounded depth, cycle check on blocking edges only, JSON graph export; ADR-0010 |
| Declarative molecules | **Missing** | **Shipped** | Validated data templates, `(template_hash, idempotency_key)` atomic instantiation; ADR-0010 |
| Gate lifecycle | **Partial** | **Shipped** | `gate list/show/check/resolve/fact ingest` with signed adapter facts; ADR-0010 |
| Wisp lifecycle | **Partial** | **Shipped** | `wisp create/list/promote/digest/burn/gc/archive` with TTL/expiry; ADR-0010 |
| Backup/import/restore lifecycle | **Partial** | **Shipped** | `backup list/preview/restore/prune` with exact divergence diffing; ADR-0011 |
| Agent setup lifecycle | **Partial** | **Shipped** | Non-destructive marker injection for Claude, Codex, Cursor, Factory, Mux, OpenCode, Windsurf; ADR-0010 |
| Provider adapters, real embeddings, generic distributed merging | **Deferred** | **Deliberately Out of Core** | Out-of-core signed adapter facts (`bankai gate fact ingest`) and lexical term-hash embeddings. |

## Delivery constraints

1. **Data templates, pure rules:** a molecule is validated data. A Gleamunison rule can only return a bounded decision or annotation from an immutable task view.
2. **Trust is local:** transport can carry rule source, never implicit approval or capability grants.
3. **Compatibility is a release gate:** persistent fields need canonical/serde versioning, safe legacy defaults, and import/export coverage.
4. **Failure is explicit:** unsafe cluster setup, schema mismatch, unapproved rule, projection degradation, and divergent restore return structured errors or health states.
5. **No second authority:** neither AaronDB, JSONL, nor Gleamunison can write task truth directly.

## Explicit non-claims

- Bankai is not Beads feature-parity complete at this baseline.
- Mobile rules are a durable local product surface, not a replication or task-mutation authority.
- ~~Molecules do not exist yet.~~ **Shipped under ADR-0010.**
- The clustered adapter is not certified production HA; a one-voter rehearsal and deterministic failure schedule do not substitute for live multi-host TLS/quorum recovery evidence.

## Verification baseline

Before implementing any row above, retain the baseline checks:

- `gleam format --check`
- `gleam build`
- `gleam test`
- `git diff --check`

The intended red/green additions are specified in the approved implementation plan and tracked under issue #6.
