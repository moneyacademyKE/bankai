# Managed vector projection benchmark

**Date:** 2026-08-12
**Scope:** Bankai’s AaronDB 4.2 managed HNSW projection at a single committed
workspace offset. Mnesia remains authoritative; this measures derived retrieval
only.

## Method

`bench/projection_bench.erl` synthesizes current Bankai heads, then measures:

1. Datalog build and count query,
2. BM25 build plus query,
3. legacy request-scoped HNSW build plus query,
4. managed HNSW’s initial generation build, and
5. a second managed HNSW query at the **same** source offset.

The managed path uses `bankai/vector_bridge.projected_search`, which retains a
daemon-local deterministic HNSW topology only while its corpus signature and
Mnesia committed offset match. A new offset or changed memory document produces
a new AaronDB `projection_index` generation; a partial generation is not
queryable.

Run after `gleam build`:

    mkdir -p .bench_ebin
    erlc -o .bench_ebin -pa build/dev/erlang/bankai/ebin \
      -pa build/dev/erlang/aarondb/ebin \
      -pa build/dev/erlang/gleam_stdlib/ebin \
      -pa build/dev/erlang/gleamunison/ebin bench/projection_bench.erl
    ERL_LIBS=build/dev/erlang /opt/homebrew/Cellar/erlang/29.0.3/lib/erlang/bin/erl \
      -noshell -pa .bench_ebin -pa build/dev/erlang/bankai/ebin \
      -pa build/dev/erlang/aarondb/ebin \
      -pa build/dev/erlang/gleam_stdlib/ebin \
      -pa build/dev/erlang/gleamunison/ebin \
      -eval 'projection_bench:run().' -s init stop

## Result

One warm local run on macOS / Erlang OTP 29:

| Current heads | Datalog build | Datalog count | BM25 build + query | Fresh HNSW | Managed build | Managed steady query |
|---:|---:|---:|---:|---:|---:|---:|
| 100 | 65.2 ms | 6.2 ms | 15.8 ms | 428.1 ms | 420.6 ms | **10.6 ms** |
| 1,000 | 63.7 ms | 3.6 ms | 10.8 ms | 35.1 s | 35.1 s | **79.5 ms** |
| 5,000 | 1.16 s | 20.8 ms | 57.2 ms | 101.6 s | 104.8 s | **34.1 ms** |

These figures are design evidence, not a latency SLO: they exclude socket,
Mnesia read, and JSON serialization costs; sample sizes are one warm run.

## Decision

The managed index earns its complexity. It eliminates the pathological
per-request rebuild from the semantic commands’ steady path: repeated queries
at an unchanged committed offset move from seconds to tens of milliseconds.

The initial/rebuild cost remains roughly the same as the legacy full build.
That is honest and intentional: Bankai currently rebuilds a deterministic HNSW
corpus from an authoritative Mnesia snapshot on membership change. The index is
therefore advisory, rebuildable, and explicitly non-authoritative. `doctor`
reports the source offset, generation, health, and document count; callers do
not receive semantic candidates from a partial or degraded generation.

The current term-hash embedding remains lexical. Faster retrieval does not turn
it into actual semantic understanding.
