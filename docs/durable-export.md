# Durable task-history publication (bk-d5ba)

Mnesia remains authoritative. `tasks.jsonl` is a rebuildable immutable-history
export, excluding wisps; it is not an alternative live mutation authority.

## Publication contract

`durable_export.publish` holds a process-monitored, reentrant local lock keyed by
absolute canonical file path from before watermark/snapshot capture through
publication and marker acknowledgement. Explicit export, the request pulse,
conflict-resolution refresh and backup restore all use this seam. Compaction
holds the same lock and operates on a private staging file; it updates Mnesia
before publishing authoritative history, never exposing its intermediate file.

The watermark is captured **before** loading immutable versions. These are two
transactions, deliberately not an exact snapshot/offset pair: versions are
append-only, so the snapshot includes everything committed through that lower
bound. A later mutation may be included but is never acknowledged prematurely;
the next pulse retries. Test-only workspace reset must not run concurrently with
publication. Ordinary mutations need not wait for filesystem I/O.

JSONL flush uses an exclusive private sibling, writes, syncs, closes, then renames
onto the destination. A failed write/sync/close/rename cannot advance the marker.
A process death releases the publication lock; the old complete file or new
complete file remains visible, never a truncated file. A killed process can leave
an orphan private sibling, which is never read as authority. The directory entry
is not fsynced: VM-local reference epochs invalidate persisted markers after a
restart (including power-loss recovery), forcing republication. Foreign replica
markers and pre-upgrade integer markers are also treated as unknown.

A successful custom-destination export does not mark canonical `tasks.jsonl`.
Locks are local to the owning daemon VM; independent VMs concurrently owning the
same filesystem workspace are outside the existing single-daemon contract.

## Writer audit

- `daemon_store.export_jsonl[_to]`: shared publication seam.
- `durable_export.refresh_if_stale`: same seam, freshness checked under lock.
- `sync/conflicts.refresh_export`: same seam after Mnesia promotion.
- `backup.restore`: same seam after authoritative restore, not stale backup bytes.
- `daemon_store.compact`: locked private staging; final shared publication.
- `compact.run`: legacy file-mode entry; atomic JSONL flush. Daemon supplies a
  private staging path, never canonical `tasks.jsonl`.
- `cli/tasks`, `cli/update`, `cli/sync_import`: compatibility/file-mode fixture
  writers through atomic JSONL flush, not reachable as live socket task writers.
  Their file read/modify/write operations are not transactions against Mnesia.
- `cli/maintenance` export prints JSON; backup writes timestamped `.bak` files.
  `daemon_store.backup_jsonl` likewise targets `.bak`, not the canonical export.
- `cli.run_in` builds the legacy tasks path; root live task routing uses daemon
  operations. Tests/fixtures writing directly with `simplifile` are not publishers.

## Verification

`test/bankai_durable_publication_test.erl` exercises controlled snapshot barriers,
concurrent explicit publication, failure without marker advancement, killed-lock
owner recovery, legacy/foreign epochs, custom destinations, and compaction.
`durable_export_test.gleam` invokes those regressions in the normal `make test`
suite. Existing Mnesia, conflict-resolution and backup lifecycle tests cover the
integration callers. A two-VM restart check also verified that a persisted offset
of 0 becomes -1 in the next VM and that the pulse rebuilds a deleted export.

Final receipts (2026-11-14, `/opt/homebrew/bin` on PATH):

- `gleam build`: exit 0.
- Focused EUnit: `durable_export_test`, `backup_lifecycle_test`,
  `sync_conflict_ux_test`, `mnesia_store_test`, `store_load_honesty_test`:
  55 passed, exit 0 (the durable-export wrapper also runs 10 Erlang regressions).
- `BANKAI_EMBED_BACKEND=term-hash make test`: 402 passed, no failures, exit 0;
  nested publication regression runner: all 10 passed.
- `gleam format --check src test`: exit 0.
- `git diff --check`: exit 0.
- Before implementation: the initial five publication regressions all failed
  (missing publication seam and legacy persisted marker incorrectly accepted).

This does not change compaction's existing snapshot-replacement semantics versus
concurrent task mutations, or make legacy file-mode read/modify/write operations
Mnesia transactions. The publication lock serializes publishers, not task writes.
