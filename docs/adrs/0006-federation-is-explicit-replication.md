# ADR-0006: Federation Is Explicit Replication, Not Snapshot Consensus

**Status:** Accepted
**Date:** 2026-08-08
**Decider:** moe (@designpoa)

## Context

Bankai has durable, transactional **local** task truth: one daemon owns a
workspace's Mnesia current-head and immutable-version tables. Bankai can also
export JSONL and reconcile a peer snapshot by content hash. Neither property
makes two independent daemons a consensus group.

Calling the existing snapshot union “distributed” would be bullshit. A network
partition lets two rigs advance the same stable task ID to different immutable
heads. Hash-union preserves both versions, but it cannot decide which current
head should be true. Mnesia's local transaction does not coordinate those
machines, and aarondb projections are derived views—not a replication log.

## Decision

Keep the current mechanism named **snapshot reconciliation**:

1. a peer exports immutable versions and advertised current heads;
2. a receiver authenticates the peer and validates canonical records;
3. matching versions are unioned by content hash;
4. a current-head advance is accepted only when it is compatible with the
   receiver's known causal ancestry;
5. divergent heads become an explicit conflict record, never silent
   last-writer-wins;
6. local Mnesia commits the accepted import transactionally;
7. aarondb projections rebuild from committed heads.

This is offline-capable exchange and conflict detection. It is **not** linearizable
multi-writer coordination, leader election, or Raft.

A future federation release must first create these durable domain artifacts:

| Artifact | Purpose |
|---|---|
| Rig identity key | Stable authenticated peer identity, separate from display name/address |
| Signed replication envelope | Binds origin, payload hashes, protocol version, and anti-replay sequence/cursor |
| Per-rig causal cursor/vector | Determines whether a remote head descends from, equals, or conflicts with a local head |
| Conflict record | Persists competing heads, parents, provenance, and resolution status without overwriting either version |
| Resolution command | An explicit local transaction that selects/merges a head and records why |
| Remote dependency/gate fact | A cached, signed, expiry-bearing observation—not a synchronous hidden network read |

Transport remains replaceable: authenticated TCP pull, Git-carried JSONL, or a
future relay may carry the same envelope. Transport does not decide correctness.

## Correctness invariants

1. **No remote write bypasses the local daemon.** Every accepted replication
   event commits through the same Mnesia transaction boundary as a local write.
2. **Immutable hashes never change.** Federation may add versions and conflict
   metadata; it never rewrites a canonical version.
3. **A conflict is data, not an error to discard.** Concurrent heads for one
   task ID remain inspectable until an explicit resolution transaction.
4. **Readiness is conservative.** A task with an unresolved remote dependency
   or expired gate fact is not ready. Partition must not manufacture ready work.
5. **Local work remains available offline.** Only operations that need a remote
   fact become pending; a partition must not corrupt local Mnesia state.
6. **Replays are idempotent.** Applying an already-known signed envelope changes
   neither immutable versions nor current heads.
7. **Recovery is reconstructible.** A node can rebuild derived indexes from
   Mnesia and recover replication state from durable envelopes/cursors plus a
   snapshot; no aarondb index is part of recovery truth.

## Failure model

| Failure | Required behavior |
|---|---|
| Peer unavailable / partition | Keep local commits; queue outbound envelope; mark dependent remote facts stale after expiry |
| Duplicate / replayed message | Verify identity and cursor; no-op after idempotence check |
| Concurrent same-ID updates | Preserve both immutable heads; create conflict; do not silently choose one |
| Invalid signature / unknown peer | Reject before parsing into task state; record diagnostics only |
| Daemon crash during import | Mnesia transaction exposes all accepted rows or none; retry envelope safely |
| Projection failure | Rebuild from committed Mnesia state; never roll back task truth because a search index failed |
| Key compromise / peer removal | Stop accepting that identity, retain historical provenance, and require an explicit recovery/key-rotation procedure |

## Rejected now

- **Raft implementation:** rejected until Bankai has a concrete requirement for
  online, linearizable shared ownership. Raft without membership, durable log
  migration, quorum semantics, and operational recovery is theater.
- **Mnesia multi-node replication as a shortcut:** rejected as a federation
  design. It does not replace signed identity, causality, offline conflict
  records, or remote gate semantics.
- **Last-write-wins by timestamp:** rejected. Wall-clock ordering loses agent
  work and converts clock skew into authority.

## Consequences

Bankai can honestly offer portable reconciliation today and can design toward
federation without lying about consensus. Any later implementation must add the
artifacts above, test partition/replay/conflict/recovery cases, and update the
capability matrix only after those boundaries exist.
