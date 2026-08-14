# ADR-0011: Operational Conflict Resolution, Safe Backup Lifecycles, and Public Changefeed Journal

**Status:** Accepted

**Date:** 2026-08-14

**Tracking:** [#9](https://github.com/moneyacademyKE/bankai/issues/9)

## Context

As Bankai scales to multi-agent swarms and multi-node clusters, three operational needs emerge:
1. **Replication Conflicts:** When signed peer snapshots diverge or heads collide, the conflict must be inspectable, durable, and operator-resolvable without losing causal lineage.
2. **Safe Backups & Restores:** Restoring or previewing backups must never overwrite live Mnesia tables without upfront validation and divergence calculation.
3. **Committed Changefeed Projections:** External tools, watchers, and projections require an append-only, ordered committed changefeed stream with offset resumption.

## Decision

### 1. Federation Conflicts are Durable, Non-Blocking Audit Records
- Peer conflicts are recorded atomically to `conflicts.term` outside Mnesia task heads.
- Conflicts are inspectable via `bankai sync conflicts`, daemon socket `sync_conflicts`, and MCP `sync_conflicts`.
- Operators/agents can resolve specific conflicts (`bankai sync resolve <id>`) or clear resolved states idempotently.

### 2. Backups and Divergence Previews Precede Mutation
- Backups are timestamped snapshots of immutable Mnesia version history.
- `bankai backup preview <path>` computes an exact divergence summary (added, missing, modified, identical) before any disk or database modification.
- `bankai backup restore <path>` validates all task hashes before transactionally importing the snapshot and projecting heads.
- `bankai backup prune [--keep N]` safely cleans older backups while retaining the N newest snapshots.

### 3. Public Changefeed Journal
- Bankai exposes an ordered, committed-change log via `bankai journal tail [--after <offset>]`, socket `journal_tail`, and MCP `journal_tail`.
- Events contain monotonic offsets, deterministic event IDs, operations, affected task IDs, preconditions, and content hashes.

### 4. Non-Destructive Agent Setup
- `bankai setup <agent>` injects instructions within managed markers (`<!-- BANKAI_INSTRUCTIONS_START -->` ... `<!-- BANKAI_INSTRUCTIONS_END -->`), preserving human custom guidelines.
- `bankai setup check` and `bankai setup list` report configuration status across all supported agent harnesses.

## Consequences

### Positive
- Zero data loss during peer divergence; conflicts are inspectable and resolvable.
- Backups are verifiable and reversible with clear divergence telemetry.
- Projections and external subscribers consume pure ordered change events.
- Agent instructions compose non-destructively with custom developer guidelines.

### Costs
- Backups require additional disk space until pruned.
- Operators must review recorded replication conflicts when cross-peer histories diverge.
