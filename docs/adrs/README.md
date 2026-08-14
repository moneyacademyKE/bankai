# bankai — Architecture Decision Records

Sequential, immutable. New decisions append; superseded records are retained and cross-linked.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-hybrid-content-addressing.md) | Hybrid content-addressing — SHA-256 for task state, Unison AST for mobile rules | **Accepted** | 2026-08-03 |
| [0002](0002-canonical-serialization-versioning.md) | Canonical serialization versioning | **Accepted** | 2026-08-03 |
| [0003](0003-mobile-rule-sandbox.md) | Mobile-rule sandbox | **Accepted** | 2026-08-03 |
| [0004](0004-daemon-owned-transactional-store.md) | Daemon-owned transactional task store | **Accepted** | 2026-08-07 |
| [0005](0005-bankai-native-workflow-parity.md) | Bankai-native workflow parity | **Accepted** | 2026-08-08 |
| [0006](0006-federation-is-explicit-replication.md) | Federation is explicit replication, not snapshot consensus | **Accepted** | 2026-08-08 |
| [0007](0007-aarondb-4.2-platform-authority.md) | AaronDB 4.2 platform authority and operating modes | **Accepted** | 2026-08-12 |
| [0008](0008-signed-replica-identity.md) | Signed replica identity and causal snapshot transport | **Accepted** | 2026-08-12 |
| [0009](0009-capability-authenticated-service.md) | Capability-authenticated resident service | **Accepted** | 2026-08-13 |
| [0010](0010-declarative-workflows-and-adapter-facts.md) | Declarative workflows and optional adapter facts | **Accepted** | 2026-08-13 |
| [0011](0011-conflict-resolution-and-changefeed-journal.md) | Operational conflict resolution, safe backups, and changefeed journal | **Accepted** | 2026-08-14 |
| [0012](0012-deconstruction-and-domain-focused-architecture.md) | Deconstruction and domain-focused architecture | **Accepted** | 2026-08-14 |

## Current implementation boundary

- **Shipped:** Bankai-owned Mnesia task heads and immutable versions; daemon/MCP task routing; ordered Mnesia committed changes; AaronDB durable-log/changefeed projections with checkpoint/replay and managed daemon-local vector membership; signed replica envelopes/trust/replay rejection/conflict recording; local and clustered command modes; quorum-admitted claims with leases/fences; fail-closed cluster transport configuration; operational `doctor`/socket/MCP status; JSONL interchange; complete lifecycle commands for gates, wisps, backup catalog/preview/restore/prune, and agent setup matrix (ADR-0010, ADR-0011); declarative workflow DAG molecules/templates (ADR-0010); and modular deconstruction with legacy actor sunsetting (ADR-0012).
- **Clustered scope:** the current adapter has deterministic one-voter rehearsal, command/fence semantics, and transport admission checks. It is **not evidence of a live multi-node HA deployment**; do not confuse library capability or local rehearsal with a production cluster.
- **Rule scope:** durable local Gleamunison rule artifacts, separate local approvals, ordered audits, and isolated evaluation bounded by wall clock, process heap, and BEAM reductions are available through CLI, daemon socket, and MCP. Rules receive only immutable optional-task JSON and have no task mutation authority. Rule artifact/approval replication is intentionally absent: remote arrival can never grant local execution permission.
- **Not shipped:** automatic in-core remote network calls for gate providers (out-of-core signed facts are supported via `bankai gate fact ingest`), real embedding providers (default is term-hash lexical embeddings), and a disk-persistent vector index (the managed index is daemon-local and rebuildable from Mnesia).

The dated [workflow parity contract](../reviews/2026-08-12-bankai-workflow-parity-contract.md) is the executable gap-to-target matrix.

## Evidence

- [AaronDB 4.2 platform verification witness](../verification-witness-2026-08-12-aarondb-platform.md) — 2026-08-12 migration, failure, transport, and status evidence.

## Open follow-ups

1. ~~Canonical serialization versioning for `Task` → bytes.~~ **Resolved by ADR-0002.**
2. ~~Mobile-rule sandbox kernel and resource bounds.~~ **Durable local lifecycle plus wall-clock/heap/reduction bounds are shipped under ADR-0003.**
3. Preserve one authority per concern: Mnesia for durable Bankai domain truth; AaronDB for derived views; JSONL/signed snapshots for interchange.
