# bankai

> A content-addressed task-memory graph for AI agents — durable local truth on Gleam + the BEAM VM, with derived retrieval powered by aarondb and explicit JSONL snapshot reconciliation between machines.

## What it is

**bankai** is a Jira-style board that multiple AI agents (Claude Code, Python runners, etc.) read and write together, across machines, without drifting out of sync. It runs on **Gleam + the BEAM VM** (Erlang's runtime), so you get thousands of lightweight isolated processes and automatic crash recovery for free.

## What makes it more than a todo board

Two things:

**1. Content-addressed state.** A task's identity isn't a database row ID — it's a *hash of its contents*. Edit the task → new hash. That gives a tamper-proof, mergeable history chain. Think git, but for task state instead of files.

**2. Mobile rules (the novel bit).** An agent can define a validation rule or graph query and *ship that rule to other agents by its hash*, so they execute it without recompiling a binary. That's exactly what [`gleamunison`](https://github.com/moneyacademyKE/gleamunison) is uniquely built for — and it's the part no other agent-coordination tool has.

## Installation

bankai needs **Erlang/OTP** (the escript is a BEAM archive) — its honest tradeoff
vs beads's single static Go binary. No OTP, no bankai.

```sh
# from a checkout — builds the escript and installs `bankai` on PATH
./install.sh

# or build only:
make escript   # -> ./dist/bankai (single self-contained file)
```

`install.sh` installs to `~/.local/bin` (no sudo) by default; override with
`BINDIR=/usr/local/bin ./install.sh`. It sanity-checks for `erl` and `gleam`
first.

> `dist/bankai` is a **fully portable escript**: every compiled `.beam`/`.app`
> is bundled into the one file (`gleam export escript`), so you can copy it to
> any machine with Erlang/OTP and run it — **no source tree, no per-run rebuild.**
> From source during development, use `gleam run -m bankai -- <command>`.

## Architecture

Bankai separates **operational truth**, **derived retrieval**, and **portable interchange**. The daemon is the single writer: it owns Bankai’s Mnesia tables and commits each head advance together with its immutable, content-addressed version. JSONL is no longer a live database; it is a deliberate export/import/backup/reconciliation format.

The foundational decisions are [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md), [ADR-0004](docs/adrs/0004-daemon-owned-transactional-store.md), [ADR-0005](docs/adrs/0005-bankai-native-workflow-parity.md), and [ADR-0006](docs/adrs/0006-federation-is-explicit-replication.md): keep stable task identity distinct from mobile code and rebuildable indexes, pursue workflow capability without importing Beads’s storage model, and distinguish snapshot reconciliation from federation.

| Concern | Implementation | Authority / lifetime |
|---|---|---|
| Current task heads | Bankai-owned Mnesia `bankai_current_v2` | Durable source of truth, keyed by `{workspace, task_id}` |
| Immutable task history | Bankai-owned Mnesia `bankai_versions_v2` | Durable content-addressed versions, keyed by `{workspace, content_hash}` |
| Migration checkpoint | Bankai-owned Mnesia `bankai_meta_v2` | One-time legacy JSONL bootstrap state |
| Mutations and fresh `list` / `ready` reads | UNIX-socket daemon → `daemon_store` → `mnesia_store` | Transactional daemon path |
| Full-text, temporal, and vector retrieval | aarondb Datalog, BM25, HNSW, and vector helpers | Rebuildable in-memory projections; never authoritative |
| Portable exchange | deterministic `.bankai/tasks.jsonl` | Explicit export, import, backup, and peer reconciliation |
| Mobile rules + eval | `gleamunison/codebase` + `gleamunison/repl` | Allow-listed/sandboxed code mobility |
| Graph readiness and cycle checks | bankai’s own pure graph module | Derived from current task heads |
| MCP server | bankai’s thin stdio adapter | Protocol surface over Bankai commands |

`aarondb` is deliberately **not** Bankai’s task database. It supplies derived views: Datalog-backed `history`/`analytics`, BM25 `search`, and HNSW retrieval for `duplicates --semantic` and `prime --query`. The default vector backend is a deterministic term-hash lexical embedding; it finds overlapping terminology, not genuine semantic synonyms.

The legacy in-process actors remain useful for supervision and sequencing, but Mnesia transactions—not actor memory—are the correctness boundary. Native CLI and MCP task operations route through the daemon and do not fall back to JSONL when it is unavailable. Mnesia runtime files (`Mnesia.*/`) are ignored by Git; recover a workspace by starting the daemon to bootstrap/import its JSONL snapshot, or import a known-good `bankai backup` snapshot.

## Product surface

Modeled on [beads](https://github.com/gastownhall/beads) (a Go/Dolt graph issue tracker): short hash-IDed tasks (`bk-a3f8`), full relation graph, JSON output envelopes, and portable snapshot reconciliation. Bankai provides durable local concurrency; cross-machine consensus remains a separate replication decision.

```sh
# — tasks —
bankai init                                      # create .bankai/
bankai create "title" [--label L]..              # create a task
                   [--kind K] [--priority N]     # kinds: task|bug|feature|epic|decision|chore|gate|wisp
                   [--parent <id>]                # explicit parent + hierarchical display id
                   [--due <unix-seconds>]         # timer gate only
                   [--satisfied]                  # create an already-open gate
bankai show <id>                                 # task, children, unresolved blockers, deferred state
bankai list [--label L]                          # all current heads
bankai ready [--label L]                         # active, unblocked, non-deferred, open-gate tasks
bankai ready --claim [assignee] [--label L]      # atomically select + claim ready work
bankai count [--label L]                         # number of current heads
bankai blocked [--label L]                       # tasks in the Blocked status
bankai epic <id>                                 # immediate-child roll-up for a parent
bankai cycles                                    # blocking dependency cycles
bankai duplicates                                # explicit Duplicates relations
bankai duplicates --semantic [--threshold N]     # lexical term-hash similarity candidates
bankai stale [--days N]                          # active heads not updated in N days
bankai doctor                                    # read-only task-store diagnostics

# — dependencies and consolidation —
bankai dep add <id> <target> [--type T]          # typed relation; blocking types are cycle-checked
bankai dep list <id>                             # typed outgoing relations
bankai dep tree <id>                             # cycle-safe dependency tree
bankai merge <duplicate-id> <canonical-id>       # transactional, idempotent duplicate consolidation

# — mutations —
bankai update <id> <status>                      # open|in_progress|blocked|completed|closed
bankai update <id> --claim [assignee]            # claim one named open task
bankai update <id> --label L                     # add a label
bankai update <id> --priority N                  # set priority
bankai update <id> --defer-until <unix-seconds>  # hide from ready until due
bankai update <id> --close <reason>              # close with durable reason
bankai update <gate-id> --satisfy-gate           # open a manual gate

# — derived retrieval —
bankai history <id>                              # derive immutable version timeline
bankai analytics                                 # derive status/cycle-time metrics
bankai search <query>                            # BM25 full-text search over tasks and memories
bankai prime                                     # emit agent-injection prompt with memories
bankai prime --query "topic"                     # add lexical-vector task/memory context

# — messages and memories (separate JSONL domains) —
bankai msg add <task-id> <text> [--reply <msg-id>]
bankai msg list <task-id>
bankai remember "insight"
bankai memories
bankai compact                                   # retire closed tasks → archive.jsonl
bankai gc                                        # alias of compact

# — Mnesia ↔ JSONL interchange —
bankai export                                   # write non-wisp immutable versions to .bankai/tasks.jsonl
bankai backup                                   # write a timestamped JSONL snapshot from Mnesia
bankai import <path>                            # transactionally import a portable JSONL snapshot
bankai sync --from <path>                       # reconcile an external snapshot through Mnesia
bankai sync-serve [--port N]                    # serve a current non-wisp peer snapshot over TCP
bankai sync-pull --host H [--port N]            # pull + reconcile a peer snapshot

# — infrastructure —
bankai inspect <hash>                           # render an immutable task version by hash
bankai hooks install                            # install a pre-commit hook (runs bankai gc)
bankai serve                                    # daemon: Mnesia authority + transactional task commands
bankai mcp                                      # MCP stdio server; task tools require the daemon
bankai setup <claude|codex|cursor|factory|mux|opencode|windsurf>
```

All command output is a JSON envelope — `{"ok": <json>}` on success, `{"error": "<msg>"}` on failure — so agents parse results uniformly. Task operations require `bankai serve`; memory, messaging, compaction, setup, and hooks remain local file operations.

## Status

The local transactional release is implemented and verified. Task kinds, explicit parent links, typed dependency semantics, deferral, gate state, local-only wisps, duplicate consolidation, diagnostics, MCP routing, and Mnesia-backed task reads are present.

- [x] [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md) — Accepted; storage amendment points to ADR-0004
- [x] [ADR-0002](docs/adrs/0002-canonical-serialization-versioning.md) — Accepted
- [x] [ADR-0003](docs/adrs/0003-mobile-rule-sandbox.md) — Accepted and implemented
- [x] Content-addressed immutable task versions and canonical encoding
- [x] Daemon-owned Mnesia task heads/history; transactional task commands and MCP task routing
- [x] JSONL export, import, backup, and snapshot reconciliation
- [x] aarondb derived retrieval: Datalog history/analytics, BM25 search, lexical HNSW retrieval
- [x] Task kinds, explicit parent links, typed dependencies, deferral, gates, local-only wisps, duplicate merge, and `doctor`
- [x] CI format/build/test coverage; current suite: **149 passing, 0 failures**

### Deliberately not shipped

- Cross-machine consensus, signed federation envelopes, remote dependency/gate facts, and Raft: designed in [ADR-0006](docs/adrs/0006-federation-is-explicit-replication.md), not implemented.
- Transactional molecules/templates: deferred; no `molecule` command or data model exists yet.
- Real embedding providers: the default vector backend is lexical term hashing, not synonym-aware embeddings.
- A scalable persistent vector-index lifecycle: the per-command HNSW projection is best-effort and unsuitable for large boards; see the [benchmark](docs/projection-benchmark-2026-08-08.md).
- External PR/CI gate adapters and vendor-coupled GitHub/GitLab synchronization.

## Historical Beads roadmap

The original G1–G12 roadmap and later A–G sweep are historical delivery records, not a claim of full current Beads parity. Bankai now has a stronger local transactional boundary and retrieval features Beads lacks, but it intentionally does not offer Dolt-style branching, SQL queries, or distributed consensus. See [the capability matrix](gap_analysis_bankai_vs_beads.md) and ADRs 0005–0006 for the current boundary.

## License

TBD
