# ADR-0004: Daemon-Owned Transactional Task Store

**Status:** Accepted
**Date:** 2026-08-07
**Decider:** moe (@designpoa)
**Supersedes:** ADR-0001 storage amendment (task-state persistence only)

## Context

Bankai currently has three disconnected state paths:

1. The CLI loads all `.bankai/tasks.jsonl`, mutates an in-memory `Store`, then rewrites the entire file.
2. The UNIX-socket daemon calls the same `cli.run_in` functions, so it is only a warm transport path—not a write authority.
3. `StoreActor` and `TaskActor` provide in-memory sequencing but are neither durable nor used by CLI/daemon mutations.

That cannot make multi-process mutation correct. In particular, two clients can both read the same JSONL state and overwrite one another; `ready` followed by `update --claim` has a race; and full-text/vector indexes rebuild from files on every invocation.

The task model already supplies the required immutable value identity:

- `Task.id` is the stable logical identity.
- `Task.content_hash` is the SHA-256 address of one canonical immutable version.
- Every mutation creates a newly rehashed `Task`; prior values remain history.

## Decision

Mnesia, owned by the resident Bankai daemon, is the authoritative operational database for tasks. JSONL becomes an explicit interchange artifact—not an implicit live database.

The daemon is the only process permitted to perform task mutations. CLI and MCP clients send requests over `.bankai/bankai.sock`; no-daemon task requests fail clearly rather than silently returning to JSONL writes. All task reads also route through the daemon so they observe committed Mnesia state.

### Tables

Bankai owns versioned Mnesia tables and does **not** reuse aarondb's `datoms` table.

| Table | Key | Value | Role |
|---|---|---|---|
| `bankai_current_v2` | `{workspace, stable task id}` | canonical task JSON + current `content_hash` | current-state reads and graph queries |
| `bankai_versions_v2` | `{workspace, hexadecimal content hash}` | canonical task JSON | append-only immutable task history |
| `bankai_meta_v2` | `{workspace, metadata name}` | storage schema/import checkpoint | migration idempotence and compatibility |

Records store canonical JSON text rather than Erlang representations of Gleam `Task` values. This keeps the FFI narrow, uses the existing `serde` decoder as the single encoding boundary, and avoids coupling the database schema to compiler-generated record layouts.

The tables use `disc_copies` on the local node. Table initialization and all task mutations are performed in a purpose-built `bankai_mnesia_ffi.erl`; aarondb's Mnesia adapter remains independent.

### Transaction contract

Each mutation executes one Mnesia transaction:

1. Read affected current records with write locks.
2. Validate all preconditions from that same snapshot.
3. Construct and rehash the new `Task` using Bankai's existing builders/apply functions.
4. Write the new immutable version only if its hash does not already exist.
5. Replace the stable-ID current record.
6. Commit, returning the resulting task JSON.

A transaction abort returns Bankai's normal JSON error envelope and makes no partial state visible.

### Historical implementation scope

The table below records the **initial** migration scope approved on 2026-08-07. It is not the current command boundary: subsequent work migrated all documented task reads and task mutations, including label/priority updates, defer/close/gate updates, duplicate merge, typed dependency queries, diagnostics, and JSONL import/export/reconciliation. `compact`, messages, and memories remain separate JSONL domains by design.
| Command | Transactional behavior |
|---|---|
| `create` | Validate parent (if any), calculate the next child ID under the same snapshot, insert current + version. |
| `update <id> <status>` | Lock current task, create rehashed version, replace current. |
| `update <id> --claim [assignee]` | Lock current task and atomically set `InProgress` plus assignee. A later `ready --claim` command must calculate readiness and claim in the same transaction. |
| `dep add <id> <target> [--type]` | Lock source and target, derive graph edges from transactional current state, reject a new `Blocks` cycle, then write new source version + current head. |

Label, priority, compaction, memories, messages, and rules are not silently converted by this slice. They remain on their existing paths until each has an equivalent transactional command. This prevents a fake “single writer” claim while un-migrated mutators still alter JSONL.

### Daemon protocol and process boundary

The JSON-RPC wire shape remains one request line to one response line. The implementation changes the dispatch target:

`socket.handle_request` → daemon command service → transactional repository

rather than:

`socket.handle_request` → `cli.run_in` → JSONL rewrite.

The daemon boots Mnesia and imports legacy JSONL only when `bankai_meta_v2` has no completed import marker. Its command service owns all Mnesia calls. Existing task actors may be retained as serialized in-process coordinators, but Mnesia transactions—not actor memory—are the correctness boundary. The actor layer must never acknowledge a mutation before its transaction commits.

The CLI's current fallback behavior changes for mutation methods: if socket connection fails, return `{"error":"bankai daemon required for mutations; run bankai serve"}`. This is intentional: falling back to JSONL would reintroduce the exact lost-update race being removed.

### JSONL responsibilities

`tasks.jsonl` becomes a deterministic snapshot/export format:

| Operation | Behavior |
|---|---|
| First daemon boot | Import legacy versions into `bankai_versions_v2`; select each ID's existing latest task as `bankai_current_v2`; write the meta checkpoint transactionally. |
| `export` | Read Mnesia versions/current state and write deterministic JSONL. |
| `backup` | Export a timestamped JSONL snapshot from Mnesia, never copy a live working file. |
| `import` | Parse external JSONL, validate all records, then transactionally union immutable hashes and update heads only when conflict rules permit. |
| `sync` / reconciliation | Exchange JSONL snapshots; use the existing hash-union and same-ID divergence detection; import the accepted result through the repository. |

JSONL export must include all immutable versions, preserving the current content-addressed sync semantics. A snapshot-only export of heads would destroy `history` and `inspect <hash>` behavior.

### Migration and rollback

Migration is lazy and idempotent:

1. Create/wait for Bankai-owned Mnesia tables.
2. If the metadata checkpoint is absent, parse `tasks.jsonl` using current tolerant JSONL decoding.
3. In one transaction, insert every unique content hash, derive each current head with the existing `store.current_tasks` ordering, and record the source digest/checkpoint.
4. Preserve `tasks.jsonl` untouched. It is the rollback artifact.

If import fails, the transaction aborts and legacy JSONL remains usable by the prior release. Operators can stop the daemon, retain or remove only the Bankai Mnesia directory, and run the previous JSONL-only binary; no destructive conversion occurs.

A schema mismatch must fail loudly with a migration-required error. It must never delete and recreate Bankai tables—aarondb's current convenience behavior would be catastrophic for task history.

### Current compatibility boundary

All task reads and task mutations go through the daemon/Mnesia boundary, including `list`, `ready`, `show`, graph queries, retrieval inputs, `create`, every `update` form, `dep add`, `merge`, and import/reconciliation. The MCP server routes its task tools through that same socket contract. A missing daemon returns an error; it never falls back to a task JSONL rewrite or stale snapshot read.

JSONL remains authoritative only for its separate interchange role. `compact`, memories, and messages intentionally use their own JSONL files and are not task-head mutations.
**Positive**

- Current reads become keyed instead of a full JSONL scan.
- Each requested mutation becomes atomic and durable.
- Old task hashes remain immutable and addressable.
- The daemon becomes a real single writer rather than a cache-shaped illusion.
- JSONL remains reviewable, portable, backupable, and suitable for peer reconciliation.

**Costs / limits**

- A daemon is required for task mutation; this is operationally heavier than a one-shot file CLI.
- Initial scope does not make all existing mutators transactional. They must either be migrated or be explicitly refused while the daemon store is authoritative.
- This is local-node transactional correctness, not cross-machine consensus. Networked multi-writer federation remains a separate Raft/replication decision.

## Verification requirements

- Mnesia repository tests prove create/update/claim/dep-add write both current and immutable version records atomically.
- A concurrent claim test proves only one transaction can win a contested state transition once claim preconditions are added.
- A dependency test proves a cycle cannot be committed under concurrent relation adds.
- Migration tests prove legacy JSONL imports once, preserves all hashes, and selects the same heads as `store.current_tasks`.
- Export/import/reconciliation round-trip tests prove hashes and heads are retained.
- Socket tests prove mutating requests use the daemon repository and a missing daemon never silently rewrites JSONL.
