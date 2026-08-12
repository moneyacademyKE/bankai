# AaronDB 4.2.0 Upgrade Assessment

**Date:** 2026-08-11
**Scope:** Bankai's rebuildable Datalog, BM25, and HNSW projections.

## Decision

Bankai pins `aarondb = "4.2.0"` and adopts the release through narrow Bankai
adapters. Mnesia remains the durable materialization of task heads and immutable
versions; AaronDB is neither a task store nor a second write authority.

| Concern | Owner after platform integration |
|---|---|
| Current task heads and immutable task versions | Bankai Mnesia tables, applied through the daemon |
| Canonical task encoding and content hashes | Bankai `serde` / `ast_bridge` |
| Local committed event offsets/checkpoints | Bankai Mnesia metadata |
| Datalog, BM25, and managed HNSW retrieval | AaronDB durable-log/changefeed and projection/index lifecycle |
| Exchange / backup | Bankai JSONL, explicitly imported or exported |
| Signed replica transport | Bankai replica protocol over AaronDB canonical envelopes and identity policy |
| Clustered commands, leases, and fencing | AaronDB command/consensus surfaces; idempotent Bankai Mnesia materialization |

A projection loss is repaired from Mnesia snapshot plus ordered tail. A cluster
profile cannot start without a matching Bankai transport configuration; it fails
closed instead of becoming an accidental local writer.

## Evidence

- `gleam format --check`, `gleam build`, `gleam test` (**177 passed, 0
  failures**), and `git diff --check` passed on 2026-08-12.
- The full migration/failure/status evidence is in
  [the AaronDB 4.2 platform witness](verification-witness-2026-08-12-aarondb-platform.md).
- The test log’s rule-process crash is an intentional crash-isolation test.

## 4.2.0 adoption

- deterministic HNSW and exact-oracle verification retain a bounded advisory
  retrieval path;
- Mnesia committed snapshots/tails feed AaronDB durable-log/changefeed runtime
  projections with persisted checkpoints and visible lag/failure state;
- `projection_index` manages the daemon-local vector generation and exposes
  offset, document count, generation, and queryability to `doctor`;
- signed canonical envelopes, explicit trust/revocation, replay rejection, and
  causal conflict recording protect replica snapshots; and
- explicit clustered profiles use command admission, quorum/read-index status,
  leases, and fences before materializing a Bankai mutation in Mnesia.

## Honest limits

The adapter is tested and operationally explicit, but a one-voter rehearsal and
library-level distributed-harness schedules are **not production multi-node HA
evidence**. A production claim still needs live TLS BEAM-distribution nodes,
quorum-loss/recovery drills, membership operations, persistence validation, and
service-level objectives.

The term-hash vector backend remains lexical, not semantic. The managed HNSW
projection is daemon-local and rebuildable, not a durable cross-restart index.
Remote provider gates and transactional molecules remain unimplemented.

## References

- <https://hex.pm/api/packages/aarondb/releases/4.2.0>
- <https://aarondb.hexdocs.pm/4.2.0/>
- `build/packages/aarondb/README.md` resolved by this upgrade
- Bankai: `src/bankai/aarondb_bridge.gleam`,
  `src/bankai/vector_bridge.gleam`, `src/bankai/embed.gleam`
