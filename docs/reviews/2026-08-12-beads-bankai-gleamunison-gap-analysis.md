# Beads vs Bankai vs Gleamunison — Historical Gap Analysis (August 12 Baseline)

> [!NOTE]
> **Delivery Status (2026-08-14):** This document records the pre-parity baseline at commit `04ae8c8` (177 tests). All identified capability gaps (mobile-rule productization, structured views, declarative molecules, gates, wisps, backup/restore, conflict UX, setup matrix) have since been **fully implemented and certified** across ADR-0009 through ADR-0012, bringing the verified suite to **246 passing, 0 failures**. See [`README.md`](../../README.md) and [`gap_analysis_bankai_vs_beads.md`](../../gap_analysis_bankai_vs_beads.md) for the current capability contract.

**Date:** 2026-08-12  
**Bankai evidence baseline:** `04ae8c8019428e8c6e98f8662036730df55f36fc` (`feat: adopt aarondb 4.2 platform integration`)  
**Bankai version:** `0.2.0`  
**Verification run:** `gleam format --check && gleam build && gleam test` — **177 passed, 0 failures**. The suite intentionally prints one crash report from the mobile-rule containment test. The build has nine existing unused-import/helper warnings.

## Scope and epistemic boundary

This compares **current Bankai source** with the current public Beads documentation, not the historical sections in `gap_analysis_bankai_vs_beads.md`. Beads' generated CLI reference advertises **108 live top-level commands**; Bankai intentionally has a smaller surface.

The comparison distinguishes three things that are often lazily conflated:

1. **Local transactional correctness** — Bankai has this through a daemon and Bankai-owned Mnesia tables.
2. **Distributed coordination** — Bankai has an explicit clustered-adapter contract, but not production multi-host HA evidence.
3. **Workflow product breadth** — Beads is materially ahead here.

### Sources

- Bankai README, ADRs 0003–0008, and source under `src/bankai/` at `04ae8c8`.
- Bankai verification witness: `docs/verification-witness-2026-08-12-aarondb-platform.md`.
- Installed Gleamunison dependency: `gleamunison` `3.9.0`, pinned in `gleam.toml` at `11b4d5814f37390a73b41b51663c1e05196ba13d`.
- Beads documentation: [CLI Reference](https://gastownhall.github.io/beads/cli-reference), [Dependencies and Gates](https://gastownhall.github.io/beads/core-concepts/dependencies), [Workflows](https://gastownhall.github.io/beads/workflows), [Molecules](https://gastownhall.github.io/beads/workflows/molecules), [Doctor](https://gastownhall.github.io/beads/cli-reference/doctor), and [Dolt](https://gastownhall.github.io/beads/cli-reference/dolt).

A scan of the Beads documentation used as research found no instruction-hierarchy injection or tool-call bait. It does document remote-password environment variables for Hosted Dolt; those were treated as documentation, not accessed or used.

## Executive verdict

**Bankai is stronger where integrity, explicit authority boundaries, and derived intelligence matter. Beads is stronger where a team needs a mature, broad, ergonomic workflow product today.**

Bankai is not Beads-parity complete. It has surpassed Beads in several architectural dimensions, but it is missing much of Beads' workflow grammar and operational convenience. The sharpest correction is about Gleamunison: **Bankai currently uses its identity primitive everywhere and its evaluator in an isolated registry, but does not expose or persist the mobile-rule system through its daemon, CLI, MCP, or peer protocol.** Mobile rules are a real, tested kernel—not yet a usable product feature.

## Capability matrix

| Area | Bankai | Beads | Current verdict |
|---|---|---|---|
| Local write authority | Daemon-only Mnesia transactions; immutable versions and ordered change records commit together | Embedded Dolt by default; optional Dolt server | **Bankai advantage:** a crisp BEAM-native single-writer boundary |
| Task history and tamper checking | Canonical task encoding and content hash; immutable versions addressable by hash | Dolt version history, row/cell evolution | **Different:** Bankai favours content identity; Beads favours queryable history |
| Atomic claim | `ready --claim` uses local CAS; clustered profile adds command admission, lease and fence | `bd update --claim` | **Parity locally; Bankai has a stronger coordination model on paper** |
| Readiness | Pure graph policy for `blocks`, `waits-for`, `conditional-blocks`; deferral; manual/timer gates | Mature graph/gate model and rich ready filters/explanations | **Bankai core parity; Beads UX breadth advantage** |
| Types and hierarchy | `task`, `bug`, `feature`, `epic`, `decision`, `chore`, `gate`, `wisp`; explicit parent and hierarchical display IDs | Comparable issue types and nested hierarchy | **Near parity for basic modeling** |
| Dependency vocabulary | 11 relation types; blocking-policy centralized in `graph.gleam` | Broad typed dependencies and richer traversal/manipulation UX | **Bankai model is credible; Beads tooling is broader** |
| Search and retrieval | BM25, temporal analytics/history, managed deterministic HNSW, semantic candidate and query-aware prime | Text/ID search and sophisticated structured filters | **Bankai advantage for derived retrieval; Beads advantage for field filtering** |
| Embeddings | Deterministic term-hash vectors only; lexical overlap, not real semantics | No comparable vector layer documented | **Bankai advantage, with an important quality limit** |
| Task exchange | JSONL import/export/backup and signed TCP snapshots with trust/replay/conflict recording | Dolt remotes, commits, push/pull, native branch and cell-level merge | **Beads advantage in practical collaboration** |
| Clustered claims | Explicit AaronDB command/consensus/lease/fence adapter, fail-closed config | Dolt server multi-writer path | **Bankai is architecturally richer but unproven multi-host** |
| MCP | Thin stdio MCP adapter over daemon | Mature `beads-mcp` ecosystem and integrations | **Bankai has the protocol; Beads has the ecosystem** |
| Agent setup | Writes seven project instruction-file variants | Init/setup recipes, discovery, check/remove/global/project modes | **Beads advantage** |
| Messages and memories | Threaded task messages; content-addressed memories injected into `prime` | Messaging/mail workflows and persistent memories | **Bankai covers the basic need; Beads is operationally richer** |
| Mobile executable policy | Content-hash rule registry, explicit local approval, isolated evaluation | No equivalent content-addressed executable-rule substrate evident in docs reviewed | **Bankai differentiator—but not yet product-wired** |

## Where Bankai is better

### 1. Honest authority separation

Bankai makes the critical distinctions explicit:

```text
Mnesia      = durable current task heads + immutable task versions
AaronDB     = rebuildable changefeed / Datalog / BM25 / HNSW projections
JSONL       = export, import, backup, signed snapshot reconciliation
Gleamunison = task identity + potential mobile policy/code
```

That prevents the classic failure where a search index, cache, or JSON export quietly becomes another mutable database. `mnesia_store`, `projections`, `sync_peer`, and the platform ADRs enforce this separation.

Beads' Dolt design is practical and powerful, but it necessarily couples workflow state, relational querying, version control, and distribution to one engine. Bankai is more decomplected here.

### 2. Immutable content identity, not merely version history

Every Bankai task, memory, and message uses deterministic canonical bytes and a Gleamunison SHA-256 hash. A changed task produces a new immutable version; `inspect <hash>` can retrieve that version, and authority boundaries validate that stored contents match the claimed hash.

This is stronger than a convenience identifier: it gives Bankai a verifiable value model, supports idempotent merge/replay, and makes tampering detectable. Beads has hash-based issue IDs and Dolt history, but Bankai's content hash is attached to the full canonical task value.

### 3. Derived intelligence is first-class and explicitly non-authoritative

Bankai already has capabilities Beads does not document:

- Datalog-derived immutable history and status/cycle-time analytics;
- BM25 search across tasks and memories;
- deterministic HNSW retrieval with an exact-search oracle for tests;
- `duplicates --semantic` and `prime --query`;
- daemon-lifetime AaronDB projections driven by Mnesia snapshot plus ordered tail;
- projection/index health, lag, and recovery status in `doctor`.

The caveat matters: Bankai's embedding is **term hashing**, so it ranks word overlap. It does not reliably infer that “authentication” and “login” mean related things.

### 4. Fault containment and machine-facing operation

The BEAM gives Bankai useful composition primitives:

- a resident UNIX-socket daemon instead of repeated cold starts;
- Mnesia transactions for local mutations;
- JSON envelopes on command success and failure;
- a thin stdio MCP surface over the same daemon boundary;
- an isolated mobile-rule evaluator: an unlinked process, monitor, timeout, and kill-on-timeout.

The isolated crash test intentionally panics a rule and proves the parent survives. This is a meaningful failure-containment property, not a decorative actor diagram.

### 5. Signed replication and explicit cluster safety boundaries

Bankai's signed snapshot protocol carries domain separation, signer identity, parent hashes, logical clocks, trust/revocation, replay rejection, and conflict recording. The clustered mode adds idempotent command admission, leases, fencing tokens, and ReadIndex/quorum status.

That is more semantically explicit than “sync succeeded.” But it is **not** evidence of a production HA system: the repository currently has deterministic one-voter/failure-schedule tests, not live authenticated multi-host quorum-loss recovery.

## Where Beads is better — the remaining functional gaps

### P0 — daily agent usability

| Missing or materially weaker Bankai capability | Beads capability | Why it matters |
|---|---|---|
| **Rich list/search/query filters** | Filter by status, type, priority range, assignee, labels-any/all, dates, metadata, sort, pagination; plus query expressions | Bankai `list`, `ready`, `count`, and `blocked` only expose basic label filtering. Its BM25 search is good at words, bad at operational slicing. |
| **Task fields and planning detail** | Acceptance criteria, estimates, design/notes/context, external references, arbitrary metadata, due dates and richer ownership fields | Bankai's `Task` has title, description, status, assignee, priority, labels, relations, parent, defer/closure/gate state. That is intentionally small, but insufficient for several real planning workflows. |
| **Dependency operations and visualisation** | Directional `dep list/tree`, add/remove/relate/unrelate, graph/Mermaid-oriented tooling and ready explanations | Bankai provides add/list/tree and cycle checks, but no edge removal, bidirectional relation command, direction/type filtering, graph export, or `ready --explain`. |
| **Mature gate workflow** | `gate create/list/show/check/resolve/discover`, waiters/wake-up, human/timer/GitHub PR/CI/cross-rig conditions | Bankai has manual/timer state and `--satisfy-gate`; it lacks gate lifecycle commands, reasoned evaluation, waiters, external producers, and an escalation flow. |
| **Workflow templates/molecules** | Formulas, `pour`, `mol`, bond, progress, current, distill, squash, swarm/patrol composition | Bankai has no molecule/template model or command. This is the single largest intentional workflow gap. |

### P1 — collaboration and lifecycle operations

| Missing or materially weaker Bankai capability | Beads capability | Why it matters |
|---|---|---|
| **Production-grade multi-machine path** | Mature Dolt remotes, push/pull, branch workflows, server lifecycle, cell-level merge | Bankai supports signed snapshots and a cluster adapter, but has no live multi-host HA evidence, no peer/remote management UX, and no branch-native workflow. |
| **Conflict resolution ergonomics** | Dolt history, diffs, branch handling, merge/recovery workflows | Bankai records/rejects conflicts rather than silently selecting a winner. Correct, but an operator has little interactive support to resolve them. |
| **Backup/import lifecycle** | Backup init/status/sync/restore, import dry-run/dedup/staleness policy, prune/purge/flatten | Bankai can backup/import/export and compact closed tasks, but it has no restore command, dry-run/import policy controls, safe pruning/purging lifecycle, or storage-reclaim operation. |
| **Wisp lifecycle** | List, TTL/GC, promote/squash/burn ephemeral workflow state | Bankai has local-only `Wisp` tasks excluded from export/sync. It lacks wisp listing, expiry, promotion, digest, or deliberate disposal commands. |
| **Agent integration operations** | `init` integration defaults; setup list/check/remove/global/project/custom recipes | Bankai writes a fixed instruction file for seven targets. There is no recipe discovery, health check, global install, removal, or idempotent merge of existing project instructions. |
| **Provider/import ecosystem** | GitHub/GitLab/Jira/Linear/ADO and other integrations documented by Beads | Bankai deliberately keeps provider credentials outside its core. That is a design choice, but it remains a capability gap for teams living in those systems. |

### P2 — engineering hygiene that affects trust

1. **Two persistence implementations remain in the repository.** The live path uses Mnesia through the daemon; legacy JSONL `cli.run_in` handlers and actor/store modules remain for non-task/local or fixture paths. The root entry point prevents task fallback to JSONL, which is good, but duplicate paths make future drift easier.
2. **The actor model is not the live correctness boundary.** `TaskActor` and `StoreActor` are useful experiments and testable components, but Mnesia transactions own live task correctness. Their comments should not be read as operational truth.
3. **Mobile-rule security is incomplete.** ADR-0003 still lists reduction budgets, hard per-process heap limits, capability tokens, durable audit logs, and signature-based rule trust as open follow-ups.
4. **The verified build has nine compiler warnings.** None fail the suite, but warning-free code is the cheaper invariant than a growing exception list.

## What is already close to parity

Bankai is credible for a local agent board:

- task kinds, labels, priority, parent hierarchy, deferred work;
- typed dependencies and cycle-safe readiness;
- task show/history/inspection;
- atomic claims;
- duplicate consolidation with immutable provenance;
- basic manual/timer gates;
- threaded task messages, durable memories, compaction;
- JSONL export/import/backup and signed peer snapshot pull;
- MCP and instruction-file setup;
- health/status diagnostics.

The important qualification: “close to parity” means the **core single-board loop**, not all of Beads' 108-command operating system around that loop.

## Gleamunison in Bankai: actual excellence vs current gap

### What Bankai actually uses today

The dependency is not decorative. It provides two real pieces of Bankai:

| Gleamunison capability | Current Bankai use | Why it is valuable |
|---|---|---|
| `gleamunison/identity` | Task, memory, message, and merge identity; canonical validation; short IDs derived from content hash | One opaque hash type and one hashing implementation prevent ad-hoc identity drift. Task history is a graph of immutable values, not overwritten rows. |
| `gleamunison/repl` | `rules/registry.gleam` evaluates an approved S-expression rule in a monitored, unlinked process | It enables a portable, content-addressed pure-policy kernel; a crash or timeout is contained instead of killing the daemon. |

This is where Gleamunison **already excels**: Bankai gets cryptographically stable content identity everywhere without recreating a homegrown hash type, and it has a real boundary for executing small policy code safely enough to test.

### Why this could be uniquely better than Beads

Beads formulas are reusable workflow data. Gleamunison makes it possible for Bankai to have **reusable workflow policy as immutable code**:

```text
rule source → content hash → local approval → isolated execution
```

That composition can support capabilities Beads does not obviously provide as a first-class primitive:

- a versioned validation predicate attached to a task transition;
- a reproducible “why was this work admitted?” result, including the rule hash;
- a rule artifact that can travel independently of a Bankai release;
- a safe replay of a historic rule against a historic task version;
- policy evolution without making every agent upgrade the Bankai binary first.

The key distinction is **data templates versus executable, content-addressed policy**. Bankai should not replace molecules with arbitrary code; molecules are data-shaped workflow graphs. But mobile rules can validate or derive facts about those graphs without inflating Bankai's static command model.

### The brutal truth: the mobile-rule feature is not wired into Bankai yet

Current public Bankai modules import only `gleamunison/identity` and `gleamunison/repl`. There are **no `rule` commands**, no socket routes, no MCP tools, and no daemon/Mnesia persistence for `Registry`. The registry appears only in `rules_test.gleam` and `rules/registry.gleam`.

Therefore these claims would be false today:

- “Agents can register, approve, run, or inspect a mobile rule through Bankai.”
- “Rules sync through Bankai peer replication.”
- “Rule approval/audit survives a daemon restart.”
- “A task transition is guarded by a mobile rule.”

Gleamunison's `codebase`, `storage`, `sync`, `effects`, compiler, and dynamic loader are present in the dependency but **not integrated into Bankai's product path**. Calling Bankai a mobile-code platform today would be premature.

## The Bankai-native path to make Gleamunison matter

Do not copy Beads' formula system in code. Preserve the distinction:

| Concern | Own it as | Authority |
|---|---|---|
| Reusable workflow shape | Declarative molecule/template data, if/when it earns its own model | Bankai Mnesia + immutable versions |
| Validation / derived policy | A pure Gleamunison rule artifact with explicit input/output schema | Local rule registry; never task authority |
| Execution permission | Local approval and capability policy | Operator-controlled, never replicated implicitly |
| Rule transport | Signed, content-addressed code artifact exchange | Separate from task snapshots and cluster command log |
| Task mutation | Bankai Mnesia transaction after policy result is verified | Bankai daemon / clustered admission |

### Recommended sequence

1. **Make the existing rule kernel real before adding more workflow concepts.** Add daemon/CLI/MCP commands for `rule register`, `rule approve`, `rule revoke`, `rule show`, and `rule eval`.
2. **Persist rule source and local approval separately.** Source may replicate; approval must remain local. Do not use “received from a trusted peer” as execution permission.
3. **Add durable audit records.** Store rule hash, caller, input hash, duration, outcome, and task/version references. This closes ADR-0003's observability gap.
4. **Define a tiny pure task-view contract.** A rule gets an immutable JSON/data snapshot and returns a bounded decision or derived annotation. It does not receive raw Mnesia access, filesystem access, network access, or authority to write a task.
5. **Finish resource controls before admitting serious policy.** Add a reduction budget and a per-process heap limit. Wall-clock timeout alone is not a complete resource policy.
6. **Only then use Gleamunison codebase/sync for artifacts.** Bankai's current signed snapshot replication moves task state; do not conflate it with code distribution. A code artifact must be verified, stored by content hash, and explicitly approved locally.
7. **Keep molecules declarative.** If formulas are added, have Bankai instantiate a transactionally validated task graph. Let mobile rules validate readiness, admission, or policy—not manufacture arbitrary hidden workflow state.

## Prioritized recommendation

| Priority | Work | Why this order |
|---|---|---|
| **P0** | Productize the existing Gleamunison rule kernel: persistent registry, daemon/CLI/MCP, local approval, audit, resource limits | It turns Bankai's claimed differentiator into a usable, auditable capability without adding a giant subsystem. |
| **P1** | Structured query/filter layer over current Mnesia heads | This closes the daily usability gap more cheaply than imitating SQL/Dolt. Start with status/kind/priority/assignee/labels/date filters plus `ready --explain`. |
| **P1** | Declarative molecules/formulas with transactional instantiation | This is the largest remaining Beads workflow gap. Keep templates data, dependencies explicit, and instance creation all-or-nothing. |
| **P2** | Gate lifecycle and external adapters | Add local `gate list/check/resolve` first; adapters should produce signed, expiring facts rather than smuggling network calls into readiness. |
| **P2** | Wisp lifecycle and backup/restore policy | Add list/promote/expire/burn and explicit snapshot restore/dry-run before storage reclamation. Destructive purge must remain opt-in. |
| **P3** | Multi-host cluster evidence and operator tooling | Do not claim HA until real TLS-node, quorum-loss/recovery, membership, restore, and SLO evidence exists. |
| **Rejected** | Make AaronDB or Gleamunison a second task database | Derived indexes and mobile code must never silently become competing task authorities. |

## Rich Hickey certification

The right Bankai is not “Beads rewritten in Gleam,” and it is not “a language runtime pretending to be an issue tracker.”

- **Mnesia** owns task truth.
- **AaronDB** derives searchable/replayable views.
- **Gleamunison** supplies immutable code identity and, once wired, constrained mobile policy.
- **Templates** should remain data.
- **Rules** should remain pure, explicit, auditable, and locally approved.
- **Replication** is not consensus, and an adapter is not production HA.

That separation retains what is genuinely special about Bankai while closing the workflow gaps users actually feel.
