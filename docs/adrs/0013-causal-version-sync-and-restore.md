# ADR-0013: Causal Version Ancestry, Retry-Safe Replication, and Authoritative Restore

**Status:** Accepted

**Date:** 2026-10-26

**Tracking:** `bk-09cd` (audit beads `bk-5d7e`, `bk-e6a2`, `bk-ee85`, `bk-b110`)

## Context

ADR-0008 made replication explicit and signed, and ADR-0011 made conflicts durable and
operator-resolvable. Four gaps survived both decisions, and each one was reproduced by a
failing test before anything changed (`test/causal_sync_gaps_test.gleam`):

1. **A hash is not a position in history.** `merge.merge/2` treated any same-id /
   different-hash pair as a conflict. Two rigs that both advanced from the same version
   produce two unrelated hashes, and so does one rig that merely advanced while the other
   stayed put. The importer could not distinguish "the peer is ahead of me" from "we forked",
   so it refused both. Ordinary remote edits — the common case — were blocked behind
   `import rejected: divergent task heads require reconciliation`, and the only way through
   was to delete one side's work.
2. **The replay token was consumed before the import landed.** `decode_signed_snapshot`
   marked the envelope applied while merely decoding it. A rejected import therefore ate its
   own frame: the pull failed, and retrying the identical snapshot was refused as a replay
   with nothing imported. A transient obstacle (a concurrent write, a lock timeout) turned
   into a permanently lost snapshot.
3. **Restore was not a restore.** `backup.restore` flushed the JSONL export but left the
   Mnesia version and head tables untouched, so a restore reported success while the
   authoritative store still held the pre-restore state. The JSONL export is a projection;
   restoring it alone restores a view, not the truth.
4. **Conflict resolution had a default.** A resolution record could be deleted without
   naming which side won, which silently dropped a real divergence from the audit trail.
5. **The daemon dispatch table dropped the verb.** `daemon_request/2` routed only bare
   `backup` and `sync`, so `backup restore <path>` fell through to the plain `backup`
   method and **took a backup instead of restoring one** — silently, with a success
   message. Every `sync conflicts|resolve|clear` call was rejected with
   `sync requires --from <path>`, and `sync-pull` never reached the peer code. The
   library was correct; the CLI could not invoke it.

## Decision

### 1. Parent links are persisted at the head write, inside its transaction

Ancestry lives in its own Mnesia table (`bankai_ancestry_v1`, key `{Workspace, Hash}`,
value: parent hashes). The link is written by `write_version_and_current/5` — the single
place any head advances — in the **same transaction** that reads the head being replaced.
That ordering is the whole guarantee: a concurrent writer either takes the lock first and
becomes the parent, or fails its compare-and-swap, so a link can never name a version this
workspace did not hold.

Links are append-only and union on conflict. Ancestry is monotone: a link known on either
side is true, and a hash can legitimately acquire parents from more than one writer.

### 2. Classification is a pure function, not an import side effect

`bankai/version_graph.gleam` owns the rules and touches no storage:

| Relationship | Meaning | Import action |
|---|---|---|
| `Identical` | Same bytes on both sides | Nothing to move |
| `FastForward` | Local head is an ancestor of the remote head | Accept the remote head |
| `Stale` | Remote head is an ancestor of the local head | Keep the local head |
| `Divergent` | Both advanced from a common ancestor | Record a conflict, change no head |

`mnesia_store.plan_import/4` classifies a whole snapshot without writing anything;
`apply_import/2` then writes it. Versions are facts, heads are decisions, and the two are
committed separately enough that a rejected fork still stores the peer's immutable bytes —
so a later `--keep remote` resolution has a version to promote.

The Mnesia boundary reflects the same split: `import_snapshot/4` takes an explicit `Advance`
id list, and only ids on that list may replace an existing head. Every other existing head
wins. An unclassified head (a legacy peer that sent no ancestry) therefore stays
conservative: same-id divergence is still refused, never guessed.

### 3. Ancestry travels with the snapshot, as an optional field

`bankai-replica-payload-v1` gained an `ancestry` array (`{hash, parents}`). It is decoded
with `optional_field`, defaulting to `[]`, so a peer that does not send it still
interoperates — it just cannot be classified, which degrades to the old conservative
behaviour rather than to an optimistic one.

### 4. The replay token is consumed only after a durable import

`decode_signed_snapshot` is now pure verification and decoding. It returns the signature,
and `pull_peer` calls `sync_peer.mark_applied/2` **after** the import returns `Ok`. A failed
pull leaves the token unconsumed, so the same frame can be retried once the obstacle is
cleared. Exactly-once applies to success, not to attempts.

### 5. Restore writes Mnesia first, and the export second

`backup.restore` calls `mnesia_store.restore_snapshot/2`, which replaces the workspace's
current rows and writes the backup's immutable version rows in **one** transaction
(`restore_snapshot/3` in the FFI, recorded as a `restore` changefeed operation). Only then
is `tasks.jsonl` flushed from the restored store. A restore is authoritative or it fails;
it is never a half-applied projection.

This is deliberately *not* `import_snapshot`: import preserves existing heads, restore
replaces them, because the backup is the declared truth.

### 6. Resolution requires an explicit side

`sync resolve <conflict-id> --keep local|remote` is mandatory across the CLI, the daemon
socket and MCP. The chosen side is promoted through `mnesia_store.promote_version/3`
(atomically: new version row + new current row), the export is refreshed from the version
store, and the conflict record is deleted **last** — a crash mid-resolution leaves a
resolvable record, never an orphaned head change. Free-form or legacy conflict details that
do not parse as `task=<id> local=<hash> remote=<hash>` are rejected, not guessed at.

### 7. The daemon routes each verb to its own method

`daemon_request/2` now maps `backup restore|preview|list|prune` to `backup_restore`,
`backup_preview`, `backup_list`, `backup_prune`; `sync conflicts|resolve|clear` to
`sync_conflicts`, `sync_conflict_resolve`, `sync_conflict_clear`; and `sync-pull` to
`sync_pull`. An unrecognised `sync` verb is a usage error rather than a fall-through into
the JSONL-reconcile handler, which used to answer a different question than the one asked.
Conflict resolution and clearing also ensure the identity directory before writing, so the
first `sync clear` on a workspace that never generated an identity succeeds instead of
failing with `enoent`.

## Consequences

### Positive

- Ordinary remote edits replicate without operator intervention; a fork is the only thing
  that stops the sync, which is exactly the thing a human should decide.
- A stale peer snapshot is harmless: it unions new ids and cannot roll a descendant back.
- Replication is retry-safe. Transient failures no longer destroy snapshots.
- Restore actually restores, and the changefeed records it.
- Every head change now carries causal provenance that survives export/import.

### Negative / costs

- One extra Mnesia table and one extra write per head advance.
- Snapshots grow with the ancestry array. It is bounded by history size, not by task count,
  and it is only sent for hashes the sender knows — not an unbounded log.
- Legacy peers that send no ancestry get no fast-forward: they still require manual
  resolution. That is the correct default until they upgrade.

### Neutral

- Classification is a pure function over `Dict(String, List(String))`, so it is testable
  without Mnesia and reusable by the CLI, the socket, and MCP without duplication.

## Verification

- `test/causal_sync_gaps_test.gleam` — 10 regression tests covering all five defects
  (replay-token consumption, retry after rejection, fast-forward, stale, divergent, restore,
  conflict-side requirement, and two pins that must not regress).
- Full suite: `BANKAI_EMBED_BACKEND=term-hash make test` → 328 passed, 0 failures.
- `gleam format --check src test` and `git diff --check` clean.
- Live CLI against a rebuilt escript and a real daemon: `backup restore` of a 2-task
  workspace returned to 1 task (the pre-backup one); `sync conflicts` → `{"ok":[]}`;
  `sync resolve <id>` without a side → the `--keep` usage error; `sync resolve <id> --keep
  local` → `unknown conflict`; `sync clear` → cleared; `sync-pull --port 1` → a peer
  connection error, proving it reached the peer code.

## Alternatives rejected

- **Wall-clock or logical clocks per task.** Ordering timestamps invite last-writer-wins,
  which silently discards a concurrent edit. Causality answers the actual question
  ("is this a descendant?") without needing synchronised clocks.
- **A linear revision counter per task.** Two rigs at revision 7 are not the same state, and
  a counter cannot express a fork at all.
- **Auto-merging divergent heads field by field.** There is no correct field-level merge for
  status transitions (open → completed vs open → blocked); a human choice is the only honest
  answer.
- **Marking the replay token at verify time (status quo).** Cheaper, and it loses data.
