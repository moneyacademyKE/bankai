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

## Current implementation boundary

- **Shipped:** Bankai-owned Mnesia task heads and immutable versions, daemon/MCP task routing, JSONL interchange, typed task/dependency workflow, deferral, manual/timer gates, local-only wisps, duplicate merge, diagnostics, and rebuildable aarondb retrieval projections.
- **Not shipped:** transactional molecules/templates, signed federation envelopes, remote dependency/gate facts, consensus/Raft, real embedding providers, and a scalable persistent vector-index lifecycle.

## Open follow-ups

1. ~~Canonical-serialization versioning for `Task` → bytes.~~ **Resolved by ADR-0002.**
2. ~~Mobile-rule execution sandbox / security model (pillar 2).~~ **Resolved by ADR-0003.**
3. Unify task-state + rule storage under one substrate.