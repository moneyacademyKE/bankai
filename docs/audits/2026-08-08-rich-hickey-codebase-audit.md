# Bankai Codebase Audit — Rich Hickey Gap Analysis

**Date:** 2026-08-08
**Scope:** `/Users/moe/Desktop/bankai` working tree, including uncommitted daemon/Mnesia/retrieval work.
**Method:** source and test review, public-surface tracing, `gleam format --check`, `gleam test`, Git state and CI review.

## Executive verdict

Bankai has a genuinely good architectural center: it distinguishes **authoritative operational state** (Mnesia), **immutable content-addressed versions**, **derived indexes** (aarondb/BM25/HNSW), and **portable interchange** (JSONL). That separation is the most Hickey-like part of the design. It avoids the usual mistake of treating an index, a cache, a log file, and a database as one vague blob.

The current migration, however, is not yet compositional enough to safely call it a clean v0.2 boundary. The system has accumulated command parsing, use-case orchestration, persistence policy, retrieval projection, transport policy, and output rendering into a few very large modules. Several public claims also exceed what the actual transport and MCP surfaces preserve.

**Assessment: 70/100 today.** The core model is strong; the boundaries and release discipline need work before treating the uncommitted state as a stable release.

## Verification evidence

| Check | Result |
|---|---|
| `gleam format --check` | Passed |
| `gleam test` | **149 passed, 0 failed** |
| Test runtime note | The visible rule-evaluation CRASH REPORT is intentional: its test verifies BEAM crash isolation. |
| CI | GitHub Actions runs format, dependency download, and tests on Gleam 1.17 / OTP 27. |
| Compiler hygiene | 10 warnings: unused imports, values, arguments, and test helpers. |
| Git state | Main has substantial uncommitted source, test, documentation, and architecture work plus new Mnesia modules/FFI. |

## Highest-value gaps

| Priority | Finding | Why it matters | Evidence |
|---|---|---|---|
| P0 | **Imported JSON can claim any `content_hash`; Bankai does not recompute and validate it.** | This breaks the primary invariant: immutable versions must be addressed by their actual canonical content. A malformed or malicious JSONL import can put content under a false hash, confusing identity, inspection, dedupe, and history. | `serde.task_from_json_string` reconstructs `content_hash` from JSON; `mnesia_store.import_snapshot` trusts decoded tasks and writes their supplied hash. Neither calls `ast_bridge.content_hash_valid`. |
| P0 | **Peer sync transfers current heads only, not immutable history.** | The receiving node cannot reconstruct the peer's task timeline; content-addressed history is discarded during transport. That contradicts the design's immutable-version premise and makes historical analytics/inspection node-local by accident. | `sync_peer.handle_pull` streams `mnesia_store.current_store`; `import_snapshot` receives only those versions. |
| P1 | **MCP advertises tools that cannot work.** | An agent sees a capability catalog that lies. `remember`, `memories`, and `compact` are advertised but are sent to the daemon, whose dispatcher does not support them; users get an unavailable/unknown-method failure. | `mcp.tools` advertises them; `tools_call` routes all calls through `socket.client_request`; `socket.handle_request` has no handlers for those names. |
| P1 | **The public version is internally inconsistent.** | A release consumer cannot trust compatibility reporting. The package and README say `0.2.0`, while CLI/MCP runtime constants say `0.1.0`. | `gleam.toml`; README; `src/bankai.gleam`; `src/bankai/mcp.gleam`. |
| P1 | **Large orchestration modules are god modules.** | Change coupling is rising rapidly. Policy is difficult to see, hard to test in isolation, and easy to break with a new command. | `cli.gleam` 1,293 LOC; `daemon_store.gleam` 1,142 LOC; `socket.gleam` 360 LOC; functions mix parsing, authorization, transactions, projection building, formatting, filesystem effects, and transport mapping. |
| P2 | **JSONL loading silently skips malformed records.** | Silent data loss is not fault tolerance. A recoverable import format must report rejected records and fail a transactional import when integrity is required. | `sync/jsonl.load` skips decode errors; `sync_peer.read_tasks` also skips malformed remote records. |
| P2 | **Task-head fallback based on `updated_at` is underspecified.** | The legacy in-memory store picks the `>=` timestamp winner for same-ID versions. Equal timestamps have no causal order and make `current` an incidental iteration-order decision. | `storage/store.group_latest`. Mnesia current heads correctly avoid this problem; the JSONL/bootstrap path does not. |

## Module and feature analysis

| Module / feature | What is good | Hickey gap / recommendation |
|---|---|---|
| `types`, `builder`, `canonical`, `ast_bridge` | Simple immutable records; canonical bytes explicitly exclude self-hash; stable task ID is distinct from version hash. | Make the hash invariant executable at every trust boundary. Add `validate_task` / `verified_task_from_json` and make imports reject invalid records with line/hash diagnostics. |
| `storage/store` | Opaque dict-backed immutable version store is small and understandable. | It conflates full-version collection with a head-selection policy for legacy data. Replace timestamp winner logic with explicit head records or a deterministic conflict result. |
| `mnesia_store` + Erlang FFI | Excellent narrow repository idea: Mnesia owns heads and immutable versions; CAS and batch replacement are transactional. Versioned table names avoid destructive schema migration. | Keep the FFI narrow, but validate content hashes before it. Add controlled recovery behavior for Mnesia startup/schema failure rather than broad `catch` values that collapse operational errors to strings. |
| `daemon_store` | Correctly centralizes transactional task use cases and rebuilds derived views from committed state. | Split by capability: `task_commands`, `task_queries`, `graph_queries`, `retrieval`, `maintenance`, and `replication`. Each should return domain data, not JSON. A thin adapter should render JSON. |
| `graph` | Pure graph functions, explicit blocking semantics, and readiness are excellent. Gates are modeled as data rather than vendor integrations. | Remove stale comments saying only Blocks can cycle: implementation correctly includes `WaitsFor` and `ConditionalBlocks`. Also remove the unused `TaskKind` import. Test missing blocker, equal-time behavior, and property-like cycle invariants. |
| `cli` | One output envelope shape is friendly to agents; command intent is broad. | Separate argv parsing from domain actions and JSON presentation. 1,293 LOC is not a module; it is a junk drawer wearing a trench coat. Make a typed `Command` ADT and one parser. |
| `socket` daemon | Single-writer daemon and per-connection crash isolation are sound. No JSONL mutation fallback is a correct concurrency decision. | Transport protocol calls it JSON-RPC but omits `jsonrpc: "2.0"` and forces numeric IDs. Either implement JSON-RPC 2.0 cleanly, or call it Bankai NDJSON RPC. Add socket permission/ownership policy and lifecycle tests for stale sockets. |
| `mcp` | Thin stdio adapter is the right instinct; it reuses task authority rather than reinventing persistence. | Make tool catalog derived from an actual typed command registry, then expose only commands executable through this surface. Add integration tests that invoke every advertised MCP tool. |
| `sync/jsonl`, `sync/merge`, `sync_peer` | Explicit reconciliation and rejected divergent heads are far better than last-write-wins theatre. The documentation correctly refuses to call snapshot reconciliation consensus. | Define a version-stream replication envelope containing workspace identity, schema/version, all immutable versions, current heads, checksums, and rejected-line/error semantics. Current TCP sync should not advertise history-preserving federation. Add authentication/TLS or make the unsafe LAN-only posture explicit. |
| `aarondb_bridge` | Derived Datalog/BM25 views are correctly non-authoritative. This is a clean use of a database-like tool as a projection, not the source of truth. | BM25 and Datalog rebuild per command. This is honest for small boards but needs a measured threshold and projection cache/invalidation design before scale claims. Also document that completed/closed cycle time is not workflow time unless semantics explicitly define it. |
| `embed`, `vector_bridge` | The lexical embedding is candidly named and isolated behind a one-module seam. Deterministic behavior is good. | Do not call it semantic similarity in command/UI language. `duplicates --semantic` is technically misleading with a term-hash backend; call it `--lexical` until a real embedding backend exists. The O(tokens × 256) list update is fine for tiny use but should not masquerade as scalable vector infrastructure. |
| `memory`, `message`, `compact` | Separate appendable domains are a good design direction; compaction avoids LLM-made “summaries” as truth. | These paths still bypass the Mnesia/daemon authority model and MCP integration. Decide whether they are intentionally local files or first-class daemon-managed domains, then make the command and MCP contracts agree. |
| `rules/registry` | Local approval does not sync; isolated rule execution has a time budget and crash containment. This is mature security reasoning. | The product surface does not expose a complete rule lifecycle, so this remains a well-tested internal subsystem rather than a coherent feature. Document that distinction or wire it through an explicit policy/capability boundary. |
| actors / legacy app | BEAM supervision experiments and pure message/state transformations are useful. | They are no longer the correctness boundary. Either make their remaining responsibility explicit (sequencing/supervision only) or delete/deprecate them after migration; two competing mental models are unnecessary complexity. |
| packaging / install / CI | Pinned lockfile, escript build, and a straightforward CI baseline are solid. | `install.sh` hardcodes `/opt/homebrew/bin`, a local macOS assumption incompatible with its portable-install story. Detect tool locations normally; keep developer convenience out of distributable behavior. CI should build and execute the exported escript, exercise daemon + CLI round trips, MCP tool parity, snapshot corruption, and peer-history replication. |

## Feature truth table

| Feature | Status | Audit conclusion |
|---|---|---|
| Content-addressed task versions | Partial | Strong model, but imports do not verify that hash matches content. |
| Local transactional writes | Implemented | Mnesia CAS / batch replacement form a credible single-writer boundary. |
| Graph readiness, cycles, gates, deferral | Implemented | Pure and well-separated; semantics are mostly crisp. |
| JSONL backup/import | Partial | Useful interchange, but malformed data is silently discarded and hash integrity is unchecked. |
| Peer reconciliation | Partial | Safe head-divergence rejection, but not full version-history replication and no network trust model. |
| Datalog/BM25 retrieval | Implemented for small data | Correctly derived, but rebuilt per command. |
| “Semantic” duplicates / RAG | Misnamed | It is lexical term hashing, not semantic retrieval. Documentation admits this; CLI naming should too. |
| MCP | Partial | Core daemon task commands work; advertised local operations do not. |
| Mobile rules | Internal capability | Sound local trust boundary but incomplete product integration. |
| Portable escript/install | Partial | Build intent is good; installer embeds Homebrew assumptions. |

## Recommended sequence

1. **Protect the invariant first.** Validate canonical task hash on every JSONL/TCP decode and reject the whole transactional import with structured diagnostics. Add tampered-content and forged-hash tests.
2. **Make replication truthful.** Decide whether peer sync is head snapshot exchange or immutable-history replication. If the latter, stream all versions plus heads; if the former, rename/document it as such and remove history-preservation claims.
3. **Repair the MCP contract.** Generate its tool catalog from executable handlers, or add explicit local command routing. Add a test that every listed tool completes a representative call.
4. **Decompose by capability.** First split `daemon_store` into queries, mutations, retrieval, and replication; then split CLI into parse → typed command → adapter. Do not split mechanically—move coherent data and behavior together.
5. **Remove release ambiguity.** One version source, no Homebrew path in installer, and CI that executes the built artifact end-to-end.
6. **Tighten failure semantics.** Preserve/report malformed JSONL lines, define legacy equal-timestamp head behavior, and remove all compiler warnings.

## Rich Hickey certification

**Passes:** immutable values, explicit authority, derived data treated as derived, no fake consensus, data-oriented graph rules, local trust for mobile code.

**Fails for now:** too much policy hidden in giant procedural modules; some interfaces claim more than the implementation guarantees; malformed external data is quietly transformed into absence. The right next move is not another feature. It is to make the existing truths impossible to violate and the boundaries impossible to misunderstand.
