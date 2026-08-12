# ADR-0007: AaronDB 4.2 Platform Authority and Operating Modes

**Status:** Accepted
**Date:** 2026-08-12
**Decider:** moe (@designpoa)
**Extends:** ADR-0004 and ADR-0006

## Context

Bankai 0.2.0 uses AaronDB 4.2.0 for derived Datalog, BM25, and deterministic
HNSW reads. Bankai-owned Mnesia tables remain the durable local materialization
of current task heads and immutable content-addressed versions. JSONL remains
portable interchange.

AaronDB 4.2 supplies a durable-log/changefeed contract, projection lifecycle,
managed index lifecycle, signed envelopes, identity admission, command/CAS,
Raft runtime, fencing, transport, and operations surfaces. The integration must
adopt those capabilities without making an AaronDB index authoritative or
pretending that a local Mnesia daemon is a coordinated cluster.

## Decision

Bankai has two explicit operating modes, selected by
`.bankai/bankai-platform.json`:

| Mode | Command authority | Materialized task state | Derived reads | Coordination claim |
|---|---|---|---|---|
| `local` | Resident Bankai daemon | Bankai Mnesia `current` + `versions` | AaronDB projections consumed from the Bankai committed change stream | One local transactional writer; no quorum claim |
| `clustered` | AaronDB committed Bankai command stream | Per-node idempotent Bankai Mnesia materialization | AaronDB projections from committed events | Quorum ordered commands and fenced claimant ownership |

The default profile is `local`. A profile that explicitly says `clustered` is
refused by `bankai serve` until the clustered runtime is configured. It must
never silently start an independent Mnesia writer and call that cluster mode.

### Implementation status — 2026-08-12

The clustered runtime is now an explicit serving mode: a clustered profile is started by `bankai serve` through the clustered daemon path, while direct local serving rejects the same profile. Cluster-visible claims are admitted through AaronDB’s command/consensus/lease boundary, then materialized once in Bankai Mnesia using the committed command ID. Claim responses disclose the fence and commit index. Claimant-owned status transitions require `update <id> --fence <token> <status>`; unfenced clustered transitions are rejected. `doctor`, socket `cluster_status`, and MCP `platform_status` report local/cluster mode, leader, commit/read indexes, quorum state, live lease count, projection/index health, transport admission, and recovery state.

Clustered serving fails closed unless `.bankai/cluster-transport.json` matches the platform profile’s cluster/node identity and passes AaronDB identity checks for active membership, issuer, bounded RPC size, and reconnect limits. The configured transport is BEAM distribution with TLS supplied by the operator; Bankai does not create an unauthenticated TCP fallback.

A one-voter profile is supported for deterministic local cluster rehearsal. It exercises the same command, fence, status, and transport-admission boundaries, but it is **not** evidence of multi-node HA. Multi-host TLS-distribution deployment, quorum-loss recovery drills, and operating SLOs remain deployment evidence that must be produced before a production-HA claim.

## Ownership

| Concern | Owner |
|---|---|
| Bankai task schema, canonical serialization, immutable content hashes, workflow validation, and authorization | Bankai |
| Current-head and immutable-version materialization | Bankai-owned Mnesia tables |
| Ordered committed-change consumption, derived Datalog/BM25/vector state, projection/index checkpoints and health | AaronDB 4.2 |
| Cluster command admission, replicated ordering, leases, and fencing | AaronDB 4.2 in `clustered` mode only |
| Portable import/export/backup | JSONL |

AaronDB projections and vector indexes are replayable outputs. They never
admit task mutations, determine readiness, or decide claims. Local readiness
and local claims read transactional Mnesia; clustered claims require a
committed conditional command and current fence.

### Event identity and replay

Each successful Bankai task transaction will write exactly one committed event
in the same Mnesia transaction as its task-head/version changes. The event has:

- a workspace-local monotonic offset;
- an event/command idempotency ID;
- operation kind;
- previous head/precondition reference;
- affected current-head and immutable-version hashes;
- canonical payload schema version.

Consumers use snapshot-at-offset followed by a strictly ordered tail. Delivery
is at-least-once; application is idempotent by event ID and offset. A failed
Bankai task transaction exposes neither a head change nor an event.

### Wire/schema migration

Bankai event and replication payloads carry an explicit schema version. The
first profile schema is version `1`; unknown versions fail closed. Signed remote
envelopes use a Bankai-specific AaronDB envelope domain. Legacy JSONL remains a
local import format and is not treated as a signed replicated command.

### Rollback

No upgrade deletes Bankai Mnesia rows or rewrites immutable hashes.

1. Before changing profiles, export JSONL from Mnesia.
2. A local projection failure is repaired by replaying a Mnesia snapshot plus
   ordered tail; it never rolls back task state.
3. A local-mode rollback stops the daemon and restores from its Mnesia directory
   or an exported JSONL snapshot using the previous local binary.
4. A clustered-mode rollback preserves committed events and all Mnesia versions;
   it requires an explicit operator transition back to local mode rather than a
   silent no-quorum write path.

## Consequences

- Local mode retains the simpler current contract and its honest limit.
- Cluster configuration becomes explicit, inspectable, and fail-closed.
- AaronDB adoption happens behind narrow Bankai adapters rather than leaking
  AaronDB’s generic schema into task semantics.
- The project may treat AaronDB 4.2 platform APIs as stable integration targets,
  but Bankai only advertises a capability after its own adapter, migration, and
  failure behavior are implemented and tested.
