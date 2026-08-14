# bankai

> A content-addressed task-memory graph for AI agents — durable local truth on Gleam + the BEAM VM, with derived retrieval powered by aarondb and explicit JSONL snapshot reconciliation between machines.

## Why Bankai: The Modern Beads Replacement for AI Agents

**Bankai** is a high-performance, content-addressed workflow graph and issue tracking platform designed specifically for autonomous AI agents (Claude Code, Cursor, Windsurf, OpenCode, OpenCrabs, Codex, Factory, Mux) and multi-agent systems. Built with **Gleam on the Erlang BEAM VM**, it provides single-writer ACID transactional guarantees, cryptographic tamper detection, sub-5ms resident daemon latency, and seamless agent memory integration.

### Bankai vs Beads: Architectural & Capability Matrix

| Capability / Concern | Beads (`bd`) | Bankai (`bankai`) | Why Bankai is Superior for Agents |
|---|---|---|---|
| **Runtime & Concurrency** | Single Go binary | **BEAM VM + Gleam** | Fault-isolated lightweight processes, crash supervision, and resident sub-5ms daemon. |
| **Write Authority** | Embedded Dolt (SQL) | **Daemon-owned Mnesia** | Strict single-writer ACID authority without SQL engine overhead or ORM bloat. |
| **State & Versioning** | SQL row/cell commit graph | **SHA-256 Content-Addressed History** | Every version is an immutable cryptographic value addressable by hash (`bankai_versions_v2`). |
| **Workflow DAGs (Molecules)** | Imperative template subsystem | **Declarative Pure-Data Molecules** | DAG templates are immutable data; atomic instantiation via `(template_hash, idempotency_key)` (ADR-0010). |
| **External Signals & Gates** | In-band provider/network calls | **Signed Out-of-Core Adapter Facts** | Zero credentials in core; CI/GitHub facts are verified via cryptographic signatures (ADR-0010). |
| **Ephemeral Tasks (Wisps)** | Ordinary issues with tags | **First-Class Wisp Lifecycle** | Time-to-live expiry, promotion to permanent tasks, and archive-first disposal policy. |
| **Backup & Safe Restore** | Raw filesystem/Dolt copies | **Validated Catalog & Divergence Diff** | `backup preview` computes exact head divergence before any restore transaction (ADR-0011). |
| **Replication & Conflicts** | Dolt push/pull | **Signed Replica Envelopes & Conflict UX** | Explicit conflict recording with interactive CLI/socket resolution (`sync resolve\|clear`). |
| **Changefeed Journal** | Database binlogs | **Public Ordered Changefeed Tail** | Ordered committed-change stream with retention checkpointing (`bankai journal tail`). |
| **Derived Intelligence** | SQLite query cache | **AaronDB Changefeed Projections** | BM25 full-text search, Datalog temporal analytics, and lexical HNSW vector retrieval. |
| **Agent Setup Matrix** | Template generation | **Non-Destructive Marker Injection** | Idempotent `<!-- BANKAI_... -->` instruction injection for 7+ agent environments without human overwrites. |
| **Agent Memory** | `remember` text buffer | **Content-Addressed Memories** | Memories are versioned records injected into `bankai prime` alongside semantic search context. |
| **Tool Integration (MCP)** | External `beads-mcp` on PyPI | **Native stdio MCP Server** | Built-in `bankai mcp` command speaking Model Context Protocol over the warm resident daemon. |
| **Mobile Executable Rules** | Not supported | **Sandboxed Gleamunison Rules** | Content-addressed pure rules evaluated with wall-clock, heap, and BEAM reduction bounds (ADR-0003). |

---

## Installation

Bankai requires **Erlang/OTP** (the escript is a self-contained BEAM archive) — its honest tradeoff vs Beads's static Go binary. No OTP, no Bankai.

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
| Workflow molecules & DAGs | Bankai-owned Mnesia `bankai_templates_v1` | Content-addressed workflow templates; atomic instantiation via `(template_hash, idempotency_key)` |
| Gate & wisp lifecycles | Bankai-owned Mnesia `bankai_gates_v1`, `bankai_wisps_v1` | Deterministic gate waiters/facts; ephemeral wisp TTL expiry and archive-first disposal |
| Local mutations and fresh reads | UNIX-socket daemon → `daemon_store` → Mnesia | One local transactional writer; no redundant in-process actor state locks |
| Clustered mutations | AaronDB command/consensus/lease admission → idempotent Mnesia materialization | Explicit profile only; committed command ID plus fencing token |
| Full-text, temporal, and vector retrieval | AaronDB durable-log/changefeed + Datalog/BM25/HNSW projections | Rebuildable daemon-local projections; never authoritative |
| Cluster transport admission | AaronDB identity policy + `.bankai/cluster-transport.json` | Explicit TLS-distribution configuration; missing/mismatched config fails closed |
| Portable exchange | Signed TCP replica envelope or deliberate JSONL import/export | Snapshot reconciliation; not a consensus path |
| Mobile rules + eval | Durable Gleamunison artifacts + local approval/audit + bounded worker | Content-addressed source; immutable task input; wall-clock, heap, and reduction limits; never task authority |
| Graph readiness and cycle checks | Bankai’s own pure graph module | Derived from current task heads |
| MCP server | Bankai’s thin stdio adapter | Protocol surface over daemon commands |
| Resident service authentication | HMAC-authenticated AaronDB capabilities | Read/write/admin authorization at the wire edge; workspace secret is local authority |

`aarondb` is deliberately **not** Bankai’s task database. It supplies ordered committed-change consumption, restartable projection lifecycle, Datalog-backed `history`/`analytics`, BM25 `search`, managed HNSW retrieval, signed envelopes, and—only under an explicit clustered profile—command admission, leases, fences, and quorum/read-index status. The vector backend resolves at daemon boot: a reachable local ollama (nomic-embed-text) provides genuine semantic similarity; without one it degrades to a deterministic term-hash lexical embedding. Configure via BANKAI_EMBED_BACKEND (auto|ollama|term-hash), BANKAI_OLLAMA_URL, BANKAI_EMBED_MODEL.

The legacy in-process actor layer has been sunsetted (ADR-0012); direct Mnesia transactions paired with pure mutation modules (`task_mutation.gleam`, `relations.gleam`) provide the local correctness boundary with zero redundant actor-state locks. Native CLI and MCP task operations route through the daemon and do not fall back to JSONL when it is unavailable. Mnesia runtime files (`Mnesia.*/`) are ignored by Git; recover local task truth by starting the daemon to bootstrap/import its JSONL snapshot, or import a known-good `bankai backup` snapshot. Projection loss is repaired from Mnesia snapshot plus ordered tail.

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
bankai list [--label L] [--status S] [--kind K]  # filtered head view with stable sorting
            [--priority N] [--assignee A] [--compact]
bankai ready [--label L] [--compact]             # active, unblocked, non-deferred, open-gate tasks
bankai ready --explain                           # data-driven readiness rationale (blockers, gates, deferrals)
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
bankai dep add <id> <target> [--type T]          # add typed relation; blocking types are cycle-checked
bankai dep remove <id> <target> [--type T]       # remove one typed relation idempotently
bankai dep list <id> [--direction D] [--type T]  # outgoing by default; filtered traversal when options are supplied
bankai dep tree <id> [--depth N]                 # cycle-safe outgoing traversal
bankai dep graph [--type T]                      # stable JSON node/edge export
bankai dep check                                 # missing targets, blocking cycles, duplicate edges
bankai merge <duplicate-id> <canonical-id>       # transactional, idempotent duplicate consolidation

# — mutations —
bankai update <id> <status>                      # open|in_progress|blocked|completed|closed
bankai update <id> --claim [assignee]            # claim one named open task
bankai update <id> --release                     # unclaim in-progress work and return it to open
bankai update <id> --reopen                      # reopen completed or closed work
bankai update <id> --label L                     # add a label
bankai update <id> --remove-label L              # remove a label idempotently
bankai update <id> --priority N                  # set priority
bankai update <id> --defer-until <unix-seconds>  # hide from ready until due
bankai update <id> --undefer                     # clear task deferral idempotently
bankai update <id> --close <reason>              # close with durable reason
bankai update <gate-id> --satisfy-gate           # compatibility alias for local resolution
bankai gate list [--state all|open|pending]      # deterministic gate lifecycle view
bankai gate show|check <gate-id>                 # evaluation, waiters, audit/local escalation data
bankai gate resolve <gate-id> [--dry-run] [--actor A] [--reason R]
bankai gate fact ingest <gate-id> --issuer <key> --wire <json>
                                                   # verify trust/revocation/signature before atomic persistence
bankai wisp create <title> [--ttl S|--expires-at N]
bankai wisp list [--state all|active|expired]
bankai wisp promote|digest|squash|burn <wisp-id>
bankai wisp gc [--dry-run]                       # stable-ID expiry scan; archive-first disposal
bankai wisp archive [wisp-id]                    # deterministic disposal/promote audit
bankai batch --idempotency-key <key> <mutation>...
                                                   # all-or-nothing mutations; release|reopen|undefer|label_remove|status|priority

# — declarative workflows (molecules) —
bankai molecule register <path>                  # register immutable workflow DAG template
bankai molecule list                             # list registered template hashes
bankai molecule show <hash>                      # inspect template nodes, variables, and edges
bankai molecule instantiate <hash> [--idempotency-key K] [--binding var=val]
                                                   # atomically instantiate workflow DAG in Mnesia

# — mobile rules (gleamunison) —
bankai rule register <path>                      # register content-addressed pure Gleamunison rule
bankai rule list                                 # list registered rule hashes
bankai rule show <hash>                          # display rule source and AST
bankai rule approve <hash>                       # explicitly approve rule for local execution
bankai rule eval <hash> <task-id>                # evaluate rule in bounded, isolated worker process
bankai rule audit <hash>                         # inspect execution and denial audit logs
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

# — Mnesia ↔ JSONL interchange & backup lifecycle —
bankai export                                   # write non-wisp immutable versions to .bankai/tasks.jsonl
bankai backup                                   # write a timestamped JSONL snapshot from Mnesia
bankai backup list                              # catalog all available workspace backups
bankai backup preview <path>                    # preview divergence against current state before restoring
bankai backup restore <path>                    # transactionally restore a validated snapshot into Mnesia
bankai backup prune [--keep N]                  # safely prune older snapshots keeping N most recent
bankai import <path>                            # transactionally import a portable JSONL snapshot
bankai sync --from <path>                       # reconcile an external snapshot through Mnesia
bankai sync conflicts                           # list recorded replication/federation conflicts
bankai sync resolve <conflict-id>               # resolve and clear a specific conflict record
bankai sync clear                               # clear all recorded conflicts
bankai sync-serve [--port N]                    # serve a current non-wisp peer snapshot over TCP
bankai sync-pull --host H [--port N]            # pull + reconcile a peer snapshot

# — committed changefeed journal —
bankai journal tail [--after <offset>]          # tail ordered committed-change events

# — infrastructure & setup —
bankai inspect <hash>                           # render an immutable task version by hash
bankai hooks install                            # install a pre-commit hook (runs bankai gc)
bankai serve                                    # local or explicitly configured clustered daemon
bankai doctor                                   # Mnesia, projection, cluster, transport, recovery diagnostics
bankai cluster-status                           # cluster + transport + recovery status JSON
bankai mcp                                      # MCP stdio server; use platform_status for the same health view
bankai setup check                              # check agent configuration matrix status
bankai setup list                               # list supported agent integrations
bankai setup <claude|codex|cursor|factory|mux|opencode|opencrabs|windsurf>
                                                 # non-destructive instruction injection with markers

# — authenticated service capabilities —
bankai auth mint read --ttl 3600               # read-only bearer capability
bankai auth mint write --ttl 3600              # mutation-only bearer capability
```

### Authenticated resident service

`bankai serve` is a concurrent, fail-closed UNIX-socket service. Every wire request carries an HMAC-signed, expiring bearer capability. AaronDB’s `Action`/`Resource`/`Capability` policy enforces three scopes at the protocol edge: `read` can query but cannot mutate, `write` can mutate but cannot mint tokens, and `admin` subsumes both and may mint attenuated capabilities. Domain handlers never receive credentials.

The ordinary local CLI bootstraps a short-lived admin capability from `.bankai/service-auth.key`; the 32-byte secret is created with mode `0600` and is never returned. Programmatic clients call `socket.client_request_with_token(workspace, method, params, token)`. Missing, expired, tampered, or under-scoped tokens fail before dispatch. Capabilities are bearer credentials: do not log or commit them. They scope protocol clients that do not already have the workspace owner’s filesystem or code-execution authority; they are **not** a same-OS-user sandbox, because that user can read the workspace key and control the local CLI. The service remains local UNIX-domain transport; network exposure additionally requires TLS and an external identity/bootstrap policy.

All command output is a JSON envelope — `{"ok": <json>}` on success, `{"error": "<msg>"}` on failure — so agents parse results uniformly. Task operations require `bankai serve`; memory, messaging, compaction, setup, and hooks remain local file operations.

## Status

The AaronDB 4.2 platform integration is implemented and verified for Bankai’s defined local and clustered contracts. Local mode has durable Mnesia authority, ordered committed changes, restartable retrieval projections, and JSONL interchange. Clustered mode has explicit command/lease/fence admission and idempotent Mnesia materialization; it refuses to start without a matching authenticated transport profile.

- [x] [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md) — accepted; stable task identity and canonical encoding
- [x] [ADR-0002](docs/adrs/0002-deterministic-binary-task-encoding.md) — deterministic binary task encoding with version byte
- [x] [ADR-0003](docs/adrs/0003-mobile-rule-sandbox.md) — sandboxed Gleamunison mobile rules and bounded execution
- [x] [ADR-0004](docs/adrs/0004-daemon-owned-transactional-store.md) — daemon-owned Mnesia current heads and immutable versions
- [x] [ADR-0005](docs/adrs/0005-bankai-native-workflow-parity.md) — Bankai-native workflow parity, typed relations, and graph readiness
- [x] [ADR-0006](docs/adrs/0006-federation-is-explicit-replication.md) — explicit federation, snapshot exchange, and conflict tracking
- [x] [ADR-0007](docs/adrs/0007-aarondb-4.2-platform-authority.md) — local/cluster authority, committed events, projections, command/fence boundary
- [x] [ADR-0008](docs/adrs/0008-signed-replica-identity.md) — signed replica envelopes, explicit trust, replay rejection, and conflict recording
- [x] [ADR-0009](docs/adrs/0009-capability-authenticated-service.md) — signed expiring read/write/admin capabilities at the resident service edge
- [x] [ADR-0010](docs/adrs/0010-declarative-workflows-and-adapter-facts.md) — declarative workflow molecules and out-of-core adapter facts
- [x] [ADR-0011](docs/adrs/0011-conflict-resolution-and-changefeed-journal.md) — safe backups, divergence preview, conflict UX, and changefeed journal
- [x] [ADR-0012](docs/adrs/0012-deconstruction-and-domain-focused-architecture.md) — deconstruction of daemon_store/cli and actor sunsetting
- [x] AaronDB durable-log/changefeed projection runtime with checkpoints, restart/replay, vector lifecycle, and health diagnostics
- [x] Explicit clustered command admission, `ready --claim` fencing, ReadIndex/quorum status, and fail-closed TLS-distribution configuration
- [x] `doctor`, socket `cluster_status`, and MCP `platform_status` report local/cluster mode, projections, leases, transport, and recovery state
- [x] Migration rehearsal: Mnesia → JSONL export → clean Mnesia import preserves immutable versions and current head
- [x] Failure rehearsal: partition/reorder/crash/slow-follower/membership/clock schedules are evaluated by the AaronDB distributed harness; missing transport config fails closed
- [x] Current suite: **246 passing, 0 failures** on 2026-08-14

### Deliberately not shipped

- **Network service exposure:** resident service authentication is local UNIX-domain only. No network listener, TLS bootstrap, token revocation service, or production identity-provider integration is claimed.
- **Multi-node production deployment evidence:** the clustered adapter has explicit one-voter rehearsal and fail-closed transport admission, but no live multi-host TLS-distribution deployment, quorum-loss recovery drill, or performance SLO. Do not market it as production HA yet.
- **Automatic remote-provider network gates:** GitHub/CI/remote dependency facts remain outside the credential-free core; external facts are ingested via explicit signed fact envelopes (`bankai gate fact ingest`).
- **Real embedding providers:** the default vector backend is lexical term hashing, not synonym-aware embeddings.
- **Disk-persistent vector index:** the managed HNSW projection is daemon-local and rebuildable from Mnesia; it is not a durable authority or a cross-restart index cache.

## Beads Parity Status

Bankai has completed full useful-parity against Beads for agent workflow operations, as documented in the Verified Parity Matrix in [`gap_analysis_bankai_vs_beads.md`](gap_analysis_bankai_vs_beads.md) and ADRs 0001–0012. Bankai delivers durable local transactional authority, declarative workflow molecules, signed CI adapter facts, and safe backup/divergence recovery, while intentionally avoiding Dolt SQL runtime complexity.

## License

TBD
