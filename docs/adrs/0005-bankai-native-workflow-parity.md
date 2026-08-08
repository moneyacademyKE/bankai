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

The local workflow release added compatible task kinds, explicit hierarchy and dependency semantics, deferral, explainable readiness, duplicate merge, manual/timer gates, local-only wisps, and operational diagnostics. Each shipped capability is exposed through the daemon/socket/MCP boundary and preserves immutable history.

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
