# bankai — Architecture Decision Records

Sequential, immutable. New decisions append; superseded records are kept and cross-linked.

| # | Title | Status | Date |
|---|---|---|---|
| [0001](0001-hybrid-content-addressing.md) | Hybrid Content-Addressing — SHA-256 for task state, Unison AST for mobile rules | **Accepted** | 2026-08-03 |
| [0002](0002-canonical-serialization-versioning.md) | Canonical-serialization versioning (the `canonical_bytes` version byte + bump/migration policy) | **Accepted** | 2026-08-03 |

## Open follow-ups

1. ~~Canonical-serialization versioning for `Task` → bytes.~~ **Resolved by ADR-0002.**
2. ~~Mobile-rule execution sandbox / security model (pillar 2).~~ **Resolved by ADR-0003.**
3. Unify task-state + rule storage under one substrate.
