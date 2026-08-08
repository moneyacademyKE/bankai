# Projection benchmark

**Date:** 2026-08-08
**Decision:** Reject a generic daemon-local incremental projection cache for now.

## Scope

This measures the exact fresh-projection calls used by Bankai's current daemon:

- `aarondb_bridge.db_from_tasks` → Datalog current-state projection;
- `count_by_status` over that projection;
- `aarondb_bridge.search` → BM25 build plus one query;
- `vector_bridge.search` → HNSW build plus one query using the current
  deterministic 256-dimensional term-hash embedding.

The runner is `bench/projection_bench.erl`. It creates synthetic Bankai-shaped
current heads, includes one matching document per ten tasks, and measures wall
clock time through `timer:tc/3`. It does not read Mnesia, serialize JSON, or
use the socket: those costs are intentionally excluded so this is a projection
cost measurement rather than an end-to-end latency claim.

Run after `gleam build`:

    erlc -o .bench_ebin -pa build/dev/erlang/bankai/ebin \
      -pa build/dev/erlang/aarondb/ebin -pa build/dev/erlang/gleam_stdlib/ebin \
      -pa build/dev/erlang/gleamunison/ebin bench/projection_bench.erl
    ERL_LIBS=build/dev/erlang erl -noshell -pa .bench_ebin \
      -pa build/dev/erlang/bankai/ebin -pa build/dev/erlang/aarondb/ebin \
      -pa build/dev/erlang/gleam_stdlib/ebin -pa build/dev/erlang/gleamunison/ebin \
      -eval 'projection_bench:run().' -s init stop

## Result

Two consecutive macOS local-development runs on warm compiled OTP artifacts:

| Current heads | Datalog build | Datalog count query | BM25 build + query | HNSW build + query |
|---:|---:|---:|---:|---:|
| 100 | 59.2–68.9 ms | 5.3–6.2 ms | 16.0–16.2 ms | 253–283 ms |
| 1,000 | 63.8–70.3 ms | 3.6 ms | 11.3–11.5 ms | 31.3–32.9 s |
| 5,000 | 1.26–1.27 s | 24.8–25.3 ms | 63.7–65.4 ms | 51.9–73.7 s |

These samples are useful for order-of-magnitude design decisions, not a
statistical latency SLO. Repeat the run and record hardware/OTP changes before
using them in a release target.

## Interpretation

- Datalog and BM25 rebuilds are still comfortably cheap through 1,000 heads and
  are only tens of milliseconds for the measured 5,000-head workload. A shared
  cache would add invalidation, restart recovery, and stale-view bugs for no
  demonstrated user benefit.
- The current short-lived HNSW projection is not viable for large task sets.
  It reaches 31 seconds at 1,000 documents and 74 seconds at 5,000 documents.
  This is especially important because semantic duplicate discovery invokes the
  bridge per task, multiplying construction work.
- A generic `post_commit -> update every projection` cache is therefore the
  wrong response. It would make fast Datalog/BM25 paths complex and would still
  leave the vector path's algorithm/workload policy unspecified.

## Decision

**Reject generic incremental projection caching.** Keep current Datalog and
BM25 projections rebuildable from committed Mnesia heads. Do not treat their
indexes as authority and do not add a mutable cache merely because it sounds
fast.

Create a separate, measured vector-retrieval design before increasing the
semantic feature's scale. It must choose a bounded dataset/query policy and
then evaluate a daemon-local HNSW index with explicit post-commit invalidation
and full rebuild on daemon restart. Until then, HNSW remains best-effort local
retrieval, never a correctness path. This is a performance limitation, not an
excuse to claim a cache exists.
