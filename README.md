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

The foundational decisions are [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md), [ADR-0004](docs/adrs/0004-daemon-owned-transactional-store.md), [ADR-0005](docs/adrs/0005-bankai-native-workflow-parity.md), [ADR-0006](docs/adrs/0006-federation-is-explicit-replication.md), [ADR-0007](docs/adrs/0007-aarondb-4.2-platform-authority.md), [ADR-0008](docs/adrs/0008-signed-replica-identity.md), and [ADR-0009](docs/adrs/0009-capability-authenticated-service.md): task identity remains distinct from mobile code and rebuildable indexes; transaction authority remains distinct from signed snapshot exchange, quorum coordination, and capability authentication.

| Concern | Implementation | Authority / lifetime |
|---|---|---|
| Current task heads | Bankai-owned Mnesia `bankai_current_v2` | Durable source of truth, keyed by `{workspace, task_id}` |
| Immutable task history | Bankai-owned Mnesia `bankai_versions_v2` | Durable content-addressed versions, keyed by `{workspace, content_hash}` |
| Committed-change cursors | Bankai-owned Mnesia `bankai_meta_v2` | Snapshot offset, changefeed events, and projection checkpoints |
| Local mutations and fresh reads | UNIX-socket daemon → `daemon_store` → Mnesia | One local transactional writer; no quorum claim |
| Clustered mutations | AaronDB command/consensus/lease admission → idempotent Mnesia materialization | Explicit profile only; committed command ID plus fencing token |
| Full-text, temporal, and vector retrieval | AaronDB durable-log/changefeed + Datalog/BM25/HNSW projections | Rebuildable daemon-local projections; never authoritative |
| Cluster transport admission | AaronDB identity policy + `.bankai/cluster-transport.json` | Explicit TLS-distribution configuration; missing/mismatched config fails closed |
| Portable exchange | Signed TCP replica envelope or deliberate JSONL import/export | Snapshot reconciliation; not a consensus path |
| Mobile rules + eval | `gleamunison/codebase` + `gleamunison/repl` | Allow-listed/sandboxed code mobility |
| Graph readiness and cycle checks | Bankai’s own pure graph module | Derived from current task heads |
| MCP server | Bankai’s thin stdio adapter | Protocol surface over daemon commands |
| Resident service authentication | HMAC-authenticated AaronDB capabilities | Read/write/admin authorization at the wire edge; workspace secret is local authority |

`aarondb` is deliberately **not** Bankai’s task database. It supplies ordered committed-change consumption, restartable projection lifecycle, Datalog-backed `history`/`analytics`, BM25 `search`, managed HNSW retrieval, signed envelopes, and—only under an explicit clustered profile—command admission, leases, fences, and quorum/read-index status. The default vector backend is a deterministic term-hash lexical embedding; it finds overlapping terminology, not genuine semantic synonyms.

The legacy in-process actors remain useful for supervision and sequencing, but Mnesia transactions—not actor memory—are the local correctness boundary. Native CLI and MCP task operations route through the daemon and do not fall back to JSONL when it is unavailable. Mnesia runtime files (`Mnesia.*/`) are ignored by Git; recover local task truth by starting the daemon to bootstrap/import its JSONL snapshot, or import a known-good `bankai backup` snapshot. Projection loss is repaired from Mnesia snapshot plus ordered tail.

Clustered serving additionally requires `.bankai/bankai-platform.json` plus a matching `.bankai/cluster-transport.json`; the transport config names the cluster/node identity, bounded RPC limits, reconnect budget, and TLS-distribution admission facts. A missing, malformed, or mismatched transport config produces `recovery-required` status and prevents clustered serving. Use `bankai doctor` or MCP `platform_status` to inspect mode, transport, quorum, lease, projection, and recovery state without scraping logs.

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
bankai serve                                    # local or explicitly configured clustered daemon
bankai doctor                                   # Mnesia, projection, cluster, transport, recovery diagnostics
bankai cluster-status                           # cluster + transport + recovery status JSON
bankai mcp                                      # MCP stdio server; use platform_status for the same health view
bankai setup <claude|codex|cursor|factory|mux|opencode|windsurf>

# — authenticated service capabilities —
bankai auth mint read --ttl 3600               # read-only bearer capability
bankai auth mint write --ttl 3600              # mutation-only bearer capability
```

### Authenticated resident service

`bankai serve` is a concurrent, fail-closed UNIX-socket service. Every wire request carries an HMAC-signed, expiring bearer capability. AaronDB’s `Action`/`Resource`/`Capability` policy enforces three scopes at the protocol edge: `read` can query but cannot mutate, `write` can mutate but cannot mint tokens, and `admin` subsumes both and may mint attenuated capabilities. Domain handlers never receive credentials.

The ordinary local CLI bootstraps a short-lived admin capability from `.bankai/service-auth.key`; the 32-byte secret is created with mode `0600` and is never returned. Programmatic clients call `socket.client_request_with_token(workspace, method, params, token)`. Missing, expired, tampered, or under-scoped tokens fail before dispatch. Capabilities are bearer credentials: do not log or commit them. The service remains local UNIX-domain transport; network exposure additionally requires TLS and an external identity/bootstrap policy.

All command output is a JSON envelope — `{"ok": <json>}` on success, `{"error": "<msg>"}` on failure — so agents parse results uniformly. Task operations require `bankai serve`; memory, messaging, compaction, setup, and hooks remain local file operations.

## Status

The AaronDB 4.2 platform integration is implemented and verified for Bankai’s defined local and clustered contracts. Local mode has durable Mnesia authority, ordered committed changes, restartable retrieval projections, and JSONL interchange. Clustered mode has explicit command/lease/fence admission and idempotent Mnesia materialization; it refuses to start without a matching authenticated transport profile.

- [x] [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md) — accepted; stable task identity and canonical encoding
- [x] [ADR-0004](docs/adrs/0004-daemon-owned-transactional-store.md) — daemon-owned Mnesia current heads and immutable versions
- [x] [ADR-0007](docs/adrs/0007-aarondb-4.2-platform-authority.md) — local/cluster authority, committed events, projections, command/fence boundary
- [x] [ADR-0008](docs/adrs/0008-signed-replica-identity.md) — signed replica envelopes, explicit trust, replay rejection, and conflict recording
- [x] [ADR-0009](docs/adrs/0009-capability-authenticated-service.md) — signed expiring read/write/admin capabilities at the resident service edge
- [x] AaronDB durable-log/changefeed projection runtime with checkpoints, restart/replay, vector lifecycle, and health diagnostics
- [x] Explicit clustered command admission, `ready --claim` fencing, ReadIndex/quorum status, and fail-closed TLS-distribution configuration
- [x] `doctor`, socket `cluster_status`, and MCP `platform_status` report local/cluster mode, projections, leases, transport, and recovery state
- [x] Migration rehearsal: Mnesia → JSONL export → clean Mnesia import preserves immutable versions and current head
- [x] Failure rehearsal: partition/reorder/crash/slow-follower/membership/clock schedules are evaluated by the AaronDB distributed harness; missing transport config fails closed
- [x] Current suite: **182 passing, 0 failures** on 2026-08-13

### Deliberately not shipped

- **Network service exposure:** resident service authentication is local UNIX-domain only. No network listener, TLS bootstrap, token revocation service, or production identity-provider integration is claimed.
- **Multi-node production deployment evidence:** the clustered adapter has explicit one-voter rehearsal and fail-closed transport admission, but no live multi-host TLS-distribution deployment, quorum-loss recovery drill, or performance SLO. Do not market it as production HA yet.
- **Automatic remote-provider gates:** GitHub/CI/remote dependency facts remain outside the credential-free core.
- **Transactional molecules/templates:** deferred; no `molecule` command or data model exists yet.
- **Real embedding providers:** the default vector backend is lexical term hashing, not synonym-aware embeddings.
- **Disk-persistent vector index:** the managed HNSW projection is daemon-local and rebuildable from Mnesia; it is not a durable authority or a cross-restart index cache.

## Historical Beads roadmap

The original G1–G12 roadmap and later A–G sweep are historical delivery records, not a claim of full current Beads parity. Bankai now has a stronger local transactional boundary and retrieval features Beads lacks, but it intentionally does not offer Dolt-style branching, SQL queries, or distributed consensus. See [the capability matrix](gap_analysis_bankai_vs_beads.md) and ADRs 0005–0006 for the current boundary.

## License

TBD
