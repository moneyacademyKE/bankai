# ADR-0005: Bankai-Native Workflow Parity

**Status:** Accepted
**Date:** 2026-08-08
**Decider:** moe (@designpoa)

## Context

Bankai now has daemon-owned Mnesia task truth, immutable content-addressed
versions, aarondb-derived retrieval, and JSONL interchange. Beads offers a
broader workflow vocabulary, but reproducing its implementation would couple
Bankai to Dolt, SQL-first ownership, and vendor-shaped integrations that are not
required to solve Bankai's actual local-agent problems.

## Decision

Pursue **capability parity where it improves local workflow**, while preserving
Bankai's native boundaries:

| Concern | Decision |
|---|---|
| Durable task truth | Bankai-owned Mnesia behind the daemon |
| Query, ranking, temporal analysis | Rebuildable aarondb projections |
| Exchange, backup, reconciliation | Deterministic JSONL |
| Workflow extension | Structured daemon commands and allow-listed mobile rules |
| Distributed coordination | A separate, explicit federation design |

The local workflow release includes compatible task kinds, explicit hierarchy and dependency semantics, deferral, duplicate merge, complete local gate/wisp lifecycles, and operational diagnostics. Gates expose deterministic list/show/check/resolve views, derived waiters, dry-run reasons, local data-shaped escalation, and signed issuer-scoped expiry-bearing facts verified before transactional persistence. Wisps expose TTL/filtering, promotion, non-destructive digest/squash views, archive-first burn, and deterministic expiry GC while remaining excluded from portable exchange until promotion. These capabilities are exposed through the daemon/socket/MCP boundary and preserve immutable history.

**Current gaps:** backup/restore and setup lifecycle operations remain unshipped. Structured status/kind/priority/assignee/label/date filtering, stable sorting/pagination/compact views, data-shaped `ready --explain`, typed relation removal, traversal, graph export, integrity checks, transactional molecules, durable mobile rules, and gate/wisp lifecycles are shipped through the shared daemon/socket/MCP contract. No gate readiness path performs provider or network calls. The dated [workflow parity contract](../reviews/2026-08-12-bankai-workflow-parity-contract.md) records the baseline; the [completion specification](../reviews/2026-08-13-beads-parity-completion-spec.md) owns the active target.

**Molecules are not shipped.** The original plan called for transactional templates, but no `molecule` command, template data model, or implementation exists in the current source. It remains a separately scoped follow-up rather than a capability Bankai claims today.

## Rejected / deferred

- **Dolt/SQL as Bankai's authority:** rejected. It duplicates Mnesia's authority
  role and makes Bankai's task model dependent on a foreign storage engine.
- **GitHub/GitLab bidirectional sync as core workflow:** rejected. It couples the
  core model to external authentication and provider semantics.
- **Claiming JSONL reconciliation or Mnesia replication is consensus:** rejected.
  Federation needs its own causality, identity, authentication, conflict, and
  recovery design.
- **Real embedding providers and provider-specific gates:** deferred. Stable
  adapter seams come before credentials and external service policy.
- **Incremental aarondb projections:** measurement-gated. Rebuildable derived
  views remain correct by construction until measured data proves caching earns
  its lifecycle complexity.

## Consequences

- Bankai can become a richer local-agent workflow system without pretending to
  be Beads or a distributed consensus product.
- The capability matrix must distinguish shipped, partial, intentionally
different, deferred, and rejected work.
- JSONL import/export compatibility and old content hashes remain release gates
  for every model change.
