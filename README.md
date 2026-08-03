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

The original spec wanted to treat *every* task update as executable code. That's elegant but far too slow — it would blow past the sub-5ms target on every keystroke. So bankai splits the job:

- Task **state** → cheap SHA-256 hash (`gleamunison/identity.hash_bytes`) — fast, used constantly.
- **Rules that travel between agents** → full Unison hashing + sync (`hash_of_definition` + `gleamunison/sync` + `load_and_eval`) — powerful, used rarely.

Rather than rewriting the actor / graph / storage / sync plumbing from scratch, bankai **composes libraries that already exist and are tested**:

| Layer | Composed from |
|---|---|
| Graph (cycle-detect, topological sort) | [`aarondb`](https://github.com/moneyacademyKE/gleamdb) `algo/graph` |
| Actor / transactor pattern | `aarondb/transactor` |
| Content addressing + sync | `gleamunison/identity`, `gleamunison/sync` |
| Storage | `gleamunison/storage` (`mnesia` / `dets`) |

bankai's own code stays narrow: the `Task` type + canonical serializer + hash wiring, the mobile-rule registry + sync wiring, and the CLI.

## Product surface

Modeled on [beads](https://github.com/gastownhall/beads) (a Go/Dolt graph issue tracker): short hash-IDed tasks (`bk-a3f8`), dependency relations, JSON output envelopes, and mergeable sync across rigs.

```sh
bankai init                  # set up .bankai/ workspace
bankai create "title"        # create a task (id derived from its content hash)
bankai show <id>             # print a task by id
bankai list                  # all current tasks
bankai ready                 # unblocked tasks (topological filter)
bankai dep add <id> <blocker># mark <id> blocked by <blocker> (cycle-safe)
bankai update <id> <status>  # open|in_progress|blocked|completed|closed
bankai update <id> --claim   # claim atomically: in_progress + assignee
bankai inspect <hash>        # render task state for a content hash (audit)
bankai serve                 # daemon (warm JSON-RPC UNIX-socket path)
```

All command output is a JSON envelope — `{"ok": <json>}` on success, `{"error": "<msg>"}` on failure — so agents parse results uniformly.

## Status

- [x] [ADR-0001](docs/adrs/0001-hybrid-content-addressing.md) — Accepted
- [x] [ADR-0002](docs/adrs/0002-canonical-serialization-versioning.md) — Accepted
- [x] [ADR-0003](docs/adrs/0003-mobile-rule-sandbox.md) — Accepted (implemented)
- [x] Pillar 1: `Task` type + canonical serialization + `task_hash` bridge
- [x] Pillar 2: mobile-rule registry + sandbox (isolated / timeout / monitor) + `repl` eval
- [x] CLI, supervision tree, UNIX-socket daemon + client mode, **MCP stdio server**
- [x] CI (GitHub Actions: format-check → deps → test); gleamunison as a git dep
- [x] v0.1.0 released; audit BUG-01..12 addressed (10 fixed, 2 deferred — see [issue #1](https://github.com/moneyacademyKE/bankai/issues/1))
- [x] Beads-parity roadmap (G1–G12) — **all phases shipped** (82 tests)

## Roadmap (Beads parity)

All 12 items shipped, each in the lean Rich-Hickey-compatible form — the spec's
heavy options (aarondb, `gleamunison/sync`, Mist) replaced by simpler proven
precedents (git-bug, Letta/Anthropic tiering, mcp_toolkit-as-reference).

| Phase | Items | Status |
|---|---|---|
| **P0 — Make the graph usable** | G12 hash-prefix IDs · G9 `{"ok"}`/`{"error"}` envelopes · G2 `show` · G1 `dep add` · G8 `update --claim` | ✅ |
| **P1 — Agent memory** | G4 `remember` + prime injection · G3 labels + `--label` filter | ✅ |
| **P2 — Ecosystem** | G10 hierarchical IDs (`bk-a3f8.1`) · G7 `setup claude/codex` (CLAUDE.md / AGENTS.md) | ✅ |
| **P3 — Scale** | G5 `compact` (dep-free tier+retire, not aarondb) · G6 `sync --from` (git transport, not `gleamunison/sync`) · G11 `mcp` (thin stdio adapter, not mcp_toolkit/Mist) | ✅ |

Open follow-ups (beyond the roadmap): a `gleamunison/sync` *live*-sync transport
(G6's variant, when low-latency multi-rig is needed); `mcp_toolkit` HTTP/SSE
transport (G11's variant, for remote/streaming MCP clients).

## License

TBD
