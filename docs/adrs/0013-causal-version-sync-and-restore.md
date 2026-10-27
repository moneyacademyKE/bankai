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

### 6. Resolution requires an explicit side, against the heads the fork named

`sync resolve <conflict-id> --keep local|remote` is mandatory across the CLI, the daemon
socket and MCP. Resolution is one Mnesia transaction (`promote_row/6`) that:

1. reads the live current head under the write lock;
2. refuses unless that head is **one of the two sides** the conflict record names;
3. writes the promoted version row, its ancestry link, and the new current row together,
   touching no other task's head;
4. refreshes the export from the version store, then deletes the conflict record **last**.

The expected set is the *pair*, not a single hash, because either side may legitimately be
live: a merge can leave the remote head in place, so a `--keep local` resolution against a
remote-live head is a normal choice, not staleness. A head that is neither side — or no head
at all — means the task moved on or was deleted after the record was written. That is
refused with `task changed since the conflict was recorded`, the record survives for a fresh
decision, and a deleted task is never resurrected by a stale resolution. Free-form or legacy
conflict details that do not parse as `task=<id> local=<hash> remote=<hash>` are rejected,
not guessed at.

The promotion records its **parents**: both side hashes become ancestry of the promoted hash
in that same transaction. This is what makes a resolution converge rather than merely
succeed. A promoted head with no edges is invisible to classification, so the next pull from
the peer compares two nodes with no path between them and reports `divergent task heads
require reconciliation` forever — the same fork re-surfacing after every resolution, which
is exactly the defect this decision closes. With the link, the peer sees the promoted head
as a descendant of both sides and fast-forwards.

Only the promoted row is written. Resolution must never replace the workspace's head set:
an unrelated task written between the fork and the resolution is not part of the decision and
must survive it untouched.

### 7. The daemon routes each verb to its own method

`daemon_request/2` now maps `backup restore|preview|list|prune` to `backup_restore`,
`backup_preview`, `backup_list`, `backup_prune`; `sync conflicts|resolve|clear` to
`sync_conflicts`, `sync_conflict_resolve`, `sync_conflict_clear`; and `sync-pull` to
`sync_pull`. An unrecognised `sync` verb is a usage error rather than a fall-through into
the JSONL-reconcile handler, which used to answer a different question than the one asked.
Conflict resolution and clearing also ensure the identity directory before writing, so the
first `sync clear` on a workspace that never generated an identity succeeds instead of
failing with `enoent`.

Replica trust is reachable the same way: `sync_identity`, `sync_trust <public-key>` and
`sync_revoke <public-key>` are first-class daemon methods with their own CLI verbs, MCP
tools and `service_auth` allowlist entries. A peer is trusted only by explicit provisioning
of its key — there is no trust-on-first-use path, because a key that arrives over the
channel it is meant to authenticate proves nothing about who sent it.

### 8. One conflict record per fork, keyed by the fork

A rejected pull is retryable by design, so the same divergence was appended to the conflict
log on every attempt: three retries of one fork produced three records naming the same task
and the same two heads, and the operator saw a list of "conflicts" that were one conflict.
`record_conflict` now derives identity from the fork itself — `(task, local, remote)` — and
does not append a record whose three sides are already present. The log stays append-only:
nothing is rewritten or removed, and the record id is never the dedupe key, so distinct
forks and free-form diagnostics keep their full history.

### 9. Signer trust is a lifecycle policy, not two membership lists

`identity/trusted.term` now stores `{bankai_trust_policy_v1, Active, Revoked}`: each
active entry carries a raw Ed25519 public key and a nanosecond `[since, until)` validity
window, while revocation is an explicit tombstone. `bankai/sync/trust.gleam` converts that
storage into `gleamunison/trust.TrustPolicy` and calls `key_admits`, preserving the library's
named refusals (`unknown_signer`, `key_not_yet_valid`, `key_expired`, `key_revoked`). The
signer id is the canonical Base64 public key already used by the envelope's `author` field.
Gleamunison's HMAC evidence admission is not involved; AaronDB remains the Ed25519
signature verifier for both replica frames and gate facts.

Legacy flat trusted/revoked files are migrated on read: trusted keys retain effectively
unbounded validity and a legacy revocation takes precedence over a legacy active entry.
The first policy write persists the migrated representation in `trusted.term`; subsequent
reads ignore the legacy lists. Malformed storage fails closed rather than silently becoming
an empty revocation policy.

Verification admits the signer at the receiver's wall-clock `time.now()` before checking
its signature. The envelope `logical_clock` is a changefeed offset, not a timestamp. This
means expiry is a **receipt-time policy**: it does not prove when a valid signature was
created, because the current envelope carries no wall-clock issuance timestamp. Historical
admission would require a separate signed issuance-time contract, not a comparison against
the changefeed offset.

`sync trust <key> [--expires-at NS]` retains unbounded trust by default and accepts an
optional exclusive expiry. `sync rotate <old> <new> [--overlap NS] [--expires-at NS]` is
one policy transition followed by one write: the old key must be active now, the new key
starts now, and the old key expires at the earlier of its existing expiry and the requested
overlap. A zero overlap switches immediately. Distinct old/new keys and nonnegative overlap
are required. `sync revoke` replaces an active entry with a tombstone; a deliberate trust
upsert may later re-admit it, but replication never grants trust implicitly. A key has one
policy state, matching `key_admits`: rotating to an already-provisioned new key replaces its
previous window. Rotation changes local admission only; the peer must provision its new key
separately, and zero-overlap rotation intentionally fails closed for a peer still using the
old key.

The same policy governs gate-fact issuers at the fact's evaluation time, so an expired key
cannot remain valid through the other shared-identity consumer. Gate-fact expiry and key
expiry remain separate facts. The new verbs are routed through the daemon, socket, CLI,
MCP and `service_auth`; CLI and socket share `bankai/sync/trust_args.gleam` rather than
maintaining separate flag grammars. Standalone `sync identity` and `sync conflicts` may
fall back to the embedded read path when no daemon is listening; trust, revoke and rotate
remain daemon-only mutations.

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
- `test/causal_resolution_test.gleam` — 8 regression tests for the resolution defects:
  ancestry written at promotion (both convergence directions), stale-head refusal, deleted
  task not resurrected, promotion not replacing the head set, duplicate fork records, and
  live daemon rotation between two real replica identities.
- `test/trust_policy_test.gleam` — 12 deterministic lifecycle and migration tests, including
  expiry boundaries, rotation overlap, re-admission and legacy revocation precedence.
- `test/signed_replica_test.gleam` and `test/gate_facts_test.gleam` — valid signatures
  refused by expired/revoked keys; gate-fact expiry remains independent of key expiry.
- `test/sync_conflict_ux_test.gleam` — resolution through the CLI for both sides, plus
  workspace reset so authoritative-store state cannot leak between runs.
- `test/bankai_test.gleam` — standalone sync identity/conflict reads are not classified as
  mutations; trust, revoke and rotate remain daemon-gated.
- Full suite: `BANKAI_EMBED_BACKEND=term-hash make test` → 354 passed, 0 failures.
- `gleam format --check src test` and `git diff --check` clean.
- Rebuilt escript in an isolated working directory: `sync identity` returned a public key,
  `sync conflicts` returned `{"ok":[]}`, and `sync trust` without a daemon refused instead
  of mutating policy.
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
