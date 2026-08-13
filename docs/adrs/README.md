# bankai — Architecture Decision Records

Sequential, immutable. New decisions append; superseded records are kept and cross-linked.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-hybrid-content-addressing.md) | Hybrid Content-Addressing — SHA-256 for task state, Unison AST for mobile rules | **Accepted** | 2026-08-03 |
| [0002](0002-canonical-serialization-versioning.md) | Canonical-serialization versioning (the `canonical_bytes` version byte + bump/migration policy) | **Accepted** | 2026-08-03 |
| [0003](0003-mobile-rule-sandbox.md) | Mobile-rule sandbox | **Accepted** | 2026-08-03 |
| [0004](0004-daemon-owned-transactional-store.md) | Daemon-owned transactional task store | **Accepted** | 2026-08-07 |
| [0005](0005-bankai-native-workflow-parity.md) | Bankai-native workflow parity | **Accepted** | 2026-08-08 |
| [0006](0006-federation-is-explicit-replication.md) | Federation is explicit replication, not snapshot consensus | **Accepted** | 2026-08-08 |
| [0007](0007-aarondb-4.2-platform-authority.md) | AaronDB 4.2 platform authority and operating modes | **Accepted** | 2026-08-12 |
| [0008](0008-signed-replica-identity.md) | Signed replica identity and causal snapshot transport | **Accepted** | 2026-08-12 |
| [0009](0009-capability-authenticated-service.md) | Capability-authenticated resident service | **Accepted** | 2026-08-13 |

## Current implementation boundary

- **Shipped:** Bankai-owned Mnesia task heads and immutable versions; daemon/MCP task routing; ordered Mnesia committed changes; AaronDB durable-log/changefeed projections with checkpoint/replay and managed daemon-local vector membership; explicit signed replica envelopes/trust/replay rejection/conflict recording; local and clustered command modes; quorum-admitted claims with leases/fences; fail-closed cluster transport configuration; operational `doctor`/socket/MCP status; and JSONL interchange.
- **Clustered scope:** the current adapter has deterministic one-voter rehearsal, command/fence semantics, and transport admission checks. It is **not yet evidence of a live multi-node HA deployment**; do not confuse a library capability or local rehearsal with a production cluster.
- **Not shipped:** transactional molecules/templates, remote dependency/gate facts, real embedding providers, and a disk-persistent vector index (the managed index is daemon-local and rebuildable).

## Evidence

- [AaronDB 4.2 platform verification witness](../verification-witness-2026-08-12-aarondb-platform.md) — 2026-08-12 migration, failure, transport, and status evidence.

## Open follow-ups

1. ~~Canonical-serialization versioning for `Task` → bytes.~~ **Resolved by ADR-0002.**
2. ~~Mobile-rule execution sandbox / security model (pillar 2).~~ **Resolved by ADR-0003.**
3. Unify task-state + rule storage under one substrate.