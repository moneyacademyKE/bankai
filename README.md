# bankai

> A shared, content-addressed task-memory graph for swarms of AI agents — fault-tolerant, zero-drift, built on Gleam + the BEAM VM.

## What it is

**bankai** is a Jira-style board that multiple AI agents (Claude Code, Python runners, etc.) read and write together, across machines, without drifting out of sync. It runs on **Gleam + the BEAM VM** (Erlang's runtime), so you get thousands of lightweight isolated processes and automatic crash recovery for free.

## What makes it more than a todo board

Two things:

**1. Content-addressed state.** A task's identity isn't a database row ID — it's a *hash of its contents*. Edit the task → new hash. That gives a tamper-proof, mergeable history chain. Think git, but for task state instead of files.

**2. Mobile rules (the novel bit).** An agent can define a validation rule or graph query and *ship that rule to other agents by its hash*, so they execute it without recompiling a binary. That's exactly what [`gleamunison`](https://github.com/moneyacademyKE/gleamunison) is uniquely built for — and it's the part no other agent-coordination tool has.

## Architecture

The foundational decision is [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md): **separate data identity from code mobility.**

- Task **state** → cheap SHA-256 hash (`gleamunison/identity.hash_bytes`) — fast, used constantly.
- **Rules that travel between agents** → full Unison hashing + sync — powerful, used rarely.

bankai is intentionally lean — no web framework, no SQL engine, no heavy deps. Its layers:

| Layer | Implementation |
|---|---|
| Content addressing | `gleamunison/identity` (SHA-256 over canonical bytes) |
| Mobile rules + eval | `gleamunison/codebase` + `gleamunison/repl` (allow-listed, sandboxed — see [ADR-0003](docs/adrs/0003-mobile-rule-sandbox.md)) |
| Graph (cycle-detect, topo sort, ready filter) | bankai's own ~40 LOC of pure functions |
| Storage | bankai's own `dict`-backed store + `simplifile` JSONL |
| Actors + supervision | `gleam_otp` (OneForOne supervisor tree) |
| MCP server | bankai's own thin stdio adapter (no Mist — see gap-analysis research) |
| Sync | bankai's own union-merge + git transport + TCP livesync |

([aarondb](https://github.com/moneyacademyKE/gleamdb) was evaluated and **dropped** — see ADR-0001 amendment — because it drags lustre/mist/wisp web-framework deps for a graph problem that ~40 LOC of pure functions solves.)

## Product surface

Modeled on [beads](https://github.com/gastownhall/beads) (a Go/Dolt graph issue tracker): short hash-IDed tasks (`bk-a3f8`), full relation graph, JSON output envelopes, and mergeable sync across rigs.

```sh
# — tasks —
bankai init                                # set up .bankai/ workspace
bankai create "title" [--label L]..        # create a task (id = hash prefix bk-XXXX)
                   [--parent <id>]         #   subtask: bk-XXXX.N
                   [--priority N]          #   default 1
bankai show <id>                           # print a task by id
bankai list [--label L]                    # all current tasks
bankai ready [--label L]                   # unblocked tasks (topological filter)
bankai count [--label L]                   # number of current tasks
bankai blocked [--label L]                 # tasks in the Blocked state

# — relations —
bankai dep add <id> <target> [--type T]    # blocks|relates-to|duplicates|supersedes|replies-to

# — mutations —
bankai update <id> <status>                # open|in_progress|blocked|completed|closed
bankai update <id> --claim [assignee]      # claim: in_progress + assignee (default: agent)
bankai update <id> --label L               # add a label
bankai update <id> --priority N            # set the priority

# — memory & compaction —
bankai remember "insight"                  # persist a durable memory
bankai memories                            # list persisted memories
bankai prime                               # emit agent-injection prompt (with memories)
bankai compact                             # retire closed tasks → archive.jsonl

# — sync —
bankai sync [--from <path>]                # reconcile, or union-merge a remote tasks.jsonl
bankai sync-serve [--port N]               # TCP sync server (peers pull your tasks)
bankai sync-pull --host H [--port N]       # pull + union-merge a running peer's tasks

# — infrastructure —
bankai inspect <hash>                      # render task state for a content hash (audit)
bankai serve                               # daemon (warm JSON-RPC UNIX-socket path)
bankai mcp                                 # MCP stdio server (Claude Code / Cursor / any MCP client)
bankai setup <claude|codex|cursor>         # emit agent-instruction file
```

All command output is a JSON envelope — `{"ok": <json>}` on success, `{"error": "<msg>"}` on failure — so agents parse results uniformly.

## Status

- [x] [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md) — Accepted
- [x] [ADR-0002](docs/adrs/0002-canonical-serialization-versioning.md) — Accepted
- [x] [ADR-0003](docs/adrs/0003-mobile-rule-sandbox.md) — Accepted (implemented)
- [x] Pillar 1: `Task` type + canonical serialization + `task_hash` bridge
- [x] Pillar 2: mobile-rule registry + sandbox (isolated / timeout / monitor) + `repl` eval
- [x] CLI, supervision tree, UNIX-socket daemon, **MCP stdio server**
- [x] CI (GitHub Actions: format-check → deps → test); gleamunison as a git dep
- [x] v0.1.0 released; audit BUG-01..12 addressed (see [issue #1](https://github.com/moneyacademyKE/bankai/issues/1))
- [x] Beads-parity roadmap (G1–G12) — **all phases shipped**
- [x] Post-roadmap gap-closers: non-Blocks relations, priority, `count`/`blocked`, `setup cursor`, livesync
- [x] **95 tests green**

## Roadmap (Beads parity)

All 12 items shipped, each in the lean Rich-Hickey-compatible form — the spec's
heavy options (aarondb, `gleamunison/sync`, Mist) replaced by simpler proven
precedents (git-bug, Letta/Anthropic tiering, mcp_toolkit-as-reference).

| Phase | Items | Status |
|---|---|---|
| **P0 — Make the graph usable** | G12 hash-prefix IDs · G9 `{"ok"}`/`{"error"}` envelopes · G2 `show` · G1 `dep add` · G8 `update --claim` | ✅ |
| **P1 — Agent memory** | G4 `remember` + prime injection · G3 labels + `--label` filter | ✅ |
| **P2 — Ecosystem** | G10 hierarchical IDs (`bk-a3f8.1`) · G7 `setup claude/codex` | ✅ |
| **P3 — Scale** | G5 `compact` (dep-free tier+retire) · G6 `sync --from` + livesync · G11 `mcp` (thin stdio adapter) | ✅ |

### Post-roadmap closures

| Closure | What |
|---|---|
| Non-Blocks relations | `dep add --type` — all 5 RelationTypes settable (was Blocks-only) |
| Priority | `create --priority` + `update --priority` (field existed, now exposed) |
| `count` / `blocked` | query commands with `--label` filter |
| `setup cursor` | `.cursorrules` for Cursor IDE |
| Livesync | `sync-serve` / `sync-pull` — bankai-native TCP peer sync |

Open follow-ups: messaging/threading, epics, federation/mesh, GitHub/GitLab
integration, npm/PyPI distribution, SQL queries via Dolt.

## License

TBD
