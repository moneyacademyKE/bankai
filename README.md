# bankai

> A shared, content-addressed task-memory graph for swarms of AI agents — fault-tolerant, zero-drift, built on Gleam + the BEAM VM.

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
bankai epic <id>                           # roll up a parent's hierarchical children
bankai cycles                              # report dependency edges on a cycle
bankai duplicates                          # task pairs linked by a Duplicates relation
bankai stale [--days N]                    # active tasks not updated in N days (drift)

# — relations —
bankai dep add <id> <target> [--type T]    # blocks|relates-to|duplicates|supersedes|replies-to

# — mutations —
bankai update <id> <status>                # open|in_progress|blocked|completed|closed
bankai update <id> --claim [assignee]      # claim: in_progress + assignee (default: agent)
bankai update <id> --label L               # add a label
bankai update <id> --priority N            # set the priority

# — messaging —
bankai msg add <task-id> <text> [--reply <msg-id>]   # post a threaded message
bankai msg list <task-id>                   # messages for a task (newest first)

# — memory & compaction —
bankai remember "insight"                  # persist a durable memory
bankai memories                            # list persisted memories
bankai prime                               # emit agent-injection prompt (with memories)
bankai compact                             # retire closed tasks → archive.jsonl

# — maintenance —
bankai backup                              # copy tasks.jsonl to a timestamped .bak
bankai export [--format md|json]           # render tasks as a checklist or JSON
bankai gc                                  # retire closed tasks (alias of compact)

# — sync —
bankai sync [--from <path>]                # reconcile, or union-merge a remote tasks.jsonl
bankai sync --peers <file>                 # pull + merge multiple peers (host:port per line)
bankai sync-serve [--port N]               # TCP sync server (peers pull your tasks)
bankai sync-pull --host H [--port N]       # pull + union-merge a running peer's tasks

# — infrastructure —
bankai inspect <hash>                      # render task state for a content hash (audit)
bankai hooks install                       # install a pre-commit hook (runs `bankai gc`)
bankai serve                               # daemon (warm JSON-RPC UNIX-socket path)
bankai mcp                                 # MCP stdio server (Claude Code / Cursor / any MCP client)
bankai setup <claude|codex|cursor|factory|mux|opencode|windsurf>  # emit agent-instruction file
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
- [x] **Remaining-gaps sweep (Phases A–G):** graph queries (`cycles`/`duplicates`/`stale`), `epic` roll-up, task-scoped threaded `msg`, maintenance (`backup`/`export`/`gc`), multi-peer `sync --peers`, `hooks install` + setup matrix, escript distribution
- [x] **120 tests green**

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

### Remaining-gaps sweep (Phases A–G)

| Phase | What shipped (lean) | Beads's heavy option (rejected/deferred) |
|---|---|---|
| **A** graph queries | `cycles` / `duplicates` / `stale` | SQL via Dolt — **rejected** (JSONL + structured cmds) |
| **B** epics | `epic <id>` roll-up over hierarchical IDs | a separate epic entity |
| **C** messaging | content-addressed `Message` + `msg add/list --reply` | a new comms subsystem |
| **D** maintenance | `backup` / `export md\|json` / `gc` | `batch`/`apply` + GitHub bidirectional |
| **E** federation | `sync --peers <file>` multi-peer | mDNS auto-discovery — **deferred** |
| **F** hooks + setup | `hooks install` + factory/mux/opencode/windsurf | — |
| **G** distribution | escript target + `install.sh` | full npm/PyPI packaging (BEAM runtime = honest tradeoff) |

GitHub/GitLab **bidirectional** sync: **rejected as core** (couples bankai to an
external data model + auth + HTTP) — one-way `export md` covers the export half.
Full remaining detail in `gap_analysis_bankai_vs_beads.md` §9.

## License

TBD
