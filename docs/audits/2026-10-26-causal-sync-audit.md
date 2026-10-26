# Audit — causal sync, retry-safe replication, and authoritative restore (`bk-09cd`)

**Date:** 2026-10-26
**Scope:** the eight commits pushed as `e83d191..0a4cb4e` on `main`
**Method:** read the shipped code, then reproduce against the rebuilt escript (`dist/bankai`) in throwaway workspaces with real daemons and a real `sync-serve` peer.
**Verdict:** the four defects the stack set out to fix are genuinely fixed. The *detection* side of conflict handling is sound. The *resolution* side is not: the documented remedy leaves a pair permanently unable to sync.

---

## 1. What holds up

| Claim | Evidence |
|---|---|
| All 8 commits landed, tree in sync | `git rev-list --left-right --count origin/main...HEAD` → `0	0` at `0a4cb4e` |
| CI green | run `40302117750`, `headSha 0a4cb4ebe4e7…`, conclusion `success` (`gh run view`) |
| Local suite green | 328 passed, 0 failures (`BANKAI_EMBED_BACKEND=term-hash`) |
| Ancestry is captured atomically with the head it replaces | `write_version_and_current` reads the row it replaces inside the same transaction (`src/bankai_mnesia_ffi.erl:177-193`) |
| A stale snapshot cannot roll a head back | `Fresh` filter only admits ids the receiver has never held (`src/bankai_mnesia_ffi.erl:315-331`); `Stale` never enters `advances` (`src/bankai/mnesia_store.gleam:227-233`) |
| Replay token burns only after a durable import | `mark_applied` is the last statement in `pull_peer`, behind `use … <- result.try` (`src/bankai/daemon_store.gleam:729-742`) |
| Restore is atomic | `restore_snapshot/3` is one `transaction(fun() -> … end)`: delete CURRENT, union VERSIONS, write CURRENT, changefeed (`src/bankai_mnesia_ffi.erl:364-387`) |
| Restore validates before writing | `authority.restore_snapshot` runs every task through `ast_bridge.validate` first (`src/bankai/storage/authority.gleam:59-66`) |
| Ancestry is authenticated | it rides inside the signed payload (`src/bankai/sync_peer.gleam:226`) and is only parsed after `ffi_verify_snapshot` succeeds (`:297-333`) |
| Restore does not destroy the causal graph | `delete_workspace_rows(?ANCESTRY, …)` exists only in test-only `reset_workspace` (`src/bankai_mnesia_ffi.erl:52`) |
| CLI routing fixed | live: `sync conflicts` → `{"ok":[]}`; `sync resolve x` → `requires … --keep local\|remote`; `sync resolve x --keep local` → `unknown conflict: x`; `sync clear` → ok; `sync-pull --port 1` → `could not connect`; `backup restore` → restored 3→2 tasks |
| A genuine fork is refused, not silently resolved | live: two workspaces forked on `bk-f1b1` → `import rejected: divergent task heads require reconciliation` |

One gap in the *evidence*, not the code: the 8-commit push produced a single CI run at the final HEAD, so `d1c93f7`, `6b87ce9`, `f43a2da`, `b6a059a`, `7e3a8a8`, `49d4f1c` were never individually CI-verified. `gh run list --commit 0a4cb4e` also returns `[]` even though the run exists — per-commit CI queries under-report here.

---

## 2. Defects

| Bead | Severity | Summary |
|---|---|---|
| `bk-ec1a` | **4** | Resolution never converges: the promoted head is causally orphaned, so the pair can never fast-forward again |
| `bk-0f2e` | 4 | `--keep local` promotes a stale side and silently discards later edits |
| `bk-5ce5` | 3 | Promotion replaces the whole head set from a stale read, deleting concurrent work |
| `bk-0b66` | 3 | Every rejected retry appends another conflict record for the same fork |
| `bk-7d50` | 3 | No CLI/daemon/MCP surface to provision replica trust, so `sync-pull` is unusable against a real peer |

### 2.1 `bk-ec1a` — resolution never converges (headline)

`conflicts.resolve_conflict` re-stamps the chosen task's `updated_at` (`src/bankai/sync/conflicts.gleam:149-152`) and writes it through `authority.promote_version` → `ffi_restore_snapshot` (`src/bankai/storage/authority.gleam:74-86`). That produces a **new** content hash, and `restore_snapshot` writes the version row and the current row but **no ancestry link** for it (`src/bankai_mnesia_ffi.erl:364-387`). The promoted hash is therefore a node with no edges: `version_graph.ancestors/2` returns `[]` for it in both directions, so `classify` (`src/bankai/version_graph.gleam:90-103`) can only ever answer `Divergent`.

Reproduced end-to-end through the real CLI (two workspaces, `sync-serve --port 8799`):

1. fork `bk-f1b1` — A `in_progress`, B `blocked` → pull rejected, conflict recorded
2. `sync resolve <id> --keep remote` → `{"ok":"resolved conflict … keeping remote"}`
3. B's head: `status=in_progress` but `content_hash=1ec9dfe2…` — a hash neither side ever had
4. immediate re-pull → still `import rejected: divergent task heads require reconciliation`
5. `sync conflicts` went from 1 record to 2

So the documented remedy leaves the pair permanently unable to sync; the only escape is to stop pulling. `--keep local` has the same defect for the same reason.

**Fix shape:** promotion must record ancestry for the hash it creates (parent = the version it was promoted from), and/or stop re-stamping `updated_at`. The ancestry link is required regardless, because `--keep local` also creates a new hash that must be linked to its source.

### 2.2 `bk-0f2e` — stale side promoted, later edits discarded

The conflict record names the hashes the two sides had *when the fork was recorded*. Resolution never checks the live head against them, so a task that moved on afterwards is silently reverted.

Reproduced live: head `in_progress` (hash `e62211b8…`) → `sync resolve <old-id> --keep local` → `{"ok":"resolved conflict … keeping local"}` → head came back `blocked` (`cf07295b…`). The newer edit left the head with a success exit code and no warning. Same call site also resurrects a task deleted after the conflict was recorded, because heads are derived from a version-store projection rather than the current rows.

**Fix shape:** pass the expected current hash into resolution and CAS it inside the same transaction (`compare_and_put_row` already exists, `src/bankai_mnesia_ffi.erl:165-175`); refuse with "task changed since the conflict was recorded".

### 2.3 `bk-5ce5` — whole-head-set replace deletes concurrent work

`promote_version` calls `ffi_restore_snapshot(workspace, [new_row], ALL_HEADS)` where `ALL_HEADS` is a `current_store` read taken earlier (`src/bankai/sync/conflicts.gleam:130-162`), and `restore_snapshot` **deletes every CURRENT row** before rewriting (`src/bankai_mnesia_ffi.erl:366`). No CAS, and no workspace lock anywhere on the path (`grep` for lock/mutex/serialize in `socket.gleam`, `daemon_store.gleam`, `sync/conflicts.gleam` → nothing), while the daemon serves CLI, MCP and sync concurrently.

A task created between the read and the write disappears from the live head set; its version row survives, so it is recoverable, but it is gone from `list`/`count` until re-promoted. The delete-then-rewrite mechanism is proven live: `backup restore` (same FFI) of a 2-task backup after creating a 3rd task dropped the 3rd from the head set, `count` 3 → 2.

Distinct from `bk-0f2e`: CASing the conflicted task's hash does not protect unrelated concurrent tasks. This one needs the write to stop being a whole-set replace — write the single promoted row via `compare_and_put_row` and leave every other current row alone.

### 2.4 `bk-0b66` — duplicate conflict records per retry

`record_conflict/3` prepends `{nanosecond_ts, author, detail}` unconditionally (`src/bankai_replica_ffi.erl:76-81`), and `pull_peer` records once per conflicted task on **every** rejected pull (`src/bankai/daemon_store.gleam:721-728`). Retry-safety (`d1c93f7`) intentionally leaves the token unconsumed on failure, so a fork can be retried forever.

Reproduced live: three identical pulls produced three records with byte-identical `detail` (same local/remote hashes) and distinct nanosecond ids. Each is independently resolvable, so the same fork can be "resolved" several times.

**Fix shape:** dedupe on `(task, local, remote)` at record time; keep the log append-only, do not dedupe by id.

### 2.5 `bk-7d50` — no way to provision replica trust

`sync-pull` against a fresh peer fails `unknown replica author`, and nothing in the shipped surface can fix that:

- `sync_peer.trust_peer` / `revoke_peer` (backed by `bankai_replica_ffi:trust_peer/2`, `src/bankai_replica_ffi.erl:19-23`) are called **only** from `test/`
- the CLI routes `sync conflicts|resolve|clear|--from` and `sync-pull` (`src/bankai.gleam:214-224`); the usage block documents only `sync-serve` and `sync-pull` (`src/bankai/cli.gleam:991-992`)
- the MCP surface exposes `sync_conflicts` / `sync_conflict_resolve` / `sync_conflict_clear` and nothing for trust (`src/bankai/mcp.gleam:150-152`)
- there is no "print my public key" command either

The live probe only worked after deriving A's public key and calling `bankai_replica_ffi:trust_peer/2` directly from an `erl` shell against the build output. **Fix shape:** `sync identity`, `sync trust <key>`, `sync revoke <key>` as daemon methods, keeping the FFI's explicit-provisioning semantics (never trust as a side effect of verification).

---

## 3. Documented tradeoffs, not defects

- **Legacy peers.** A peer that sends no ancestry makes every same-id difference classify `Divergent`, because `ancestors(remote)` is empty. Conservative by design and stated in ADR-0013 §5; verified in code, not just in the doc.
- **Ancestry is monotone and never pruned.** A *trusted* peer's false links are permanent. The trust boundary is the explicit provisioning step, not the graph.
- **`backup restore` writes Mnesia then flushes JSONL.** If the flush fails the message says "could not replace task store" although Mnesia was already replaced. Mnesia is authoritative and the JSONL is derived, so the next export repairs it; only the wording misleads.
- **Restore unions versions.** Restoring an old backup leaves newer version rows in history. That is the content-addressed model working as intended — history is never destroyed — but `history` after a restore shows versions from beyond the restore point.
- **Over-500-line files** (`daemon_store.gleam` 765, `cli/maintenance.gleam` 548, `sync_peer.gleam` 620) were already over before this stack; the diff did not create them.

---

## 4. Reproduction kit

Two scratch workspaces plus a real peer, no mocks:

```
# fork
A: create "shared task"            → bk-f1b1
A: export                          → .bankai/tasks.jsonl
B: sync --from A/.bankai/tasks.jsonl
A: update bk-f1b1 in_progress
B: update bk-f1b1 blocked
# trust (no CLI exists — bk-7d50)
erl -pa build/dev/erlang/*/ebin -noshell -eval '… bankai_replica_ffi:trust_peer/2 …'
# peer + pull
A: sync-serve --port 8799
B: sync-pull --host 127.0.0.1 --port 8799   → import rejected (correct)
B: sync-pull ×2 more                        → 3 duplicate conflict records (bk-0b66)
B: update bk-f1b1 in_progress
B: sync resolve <old-id> --keep local        → head reverts to blocked (bk-0f2e)
B: sync resolve <id> --keep remote
B: sync-pull                                → still divergent (bk-ec1a)
```

Every scratch daemon was stopped afterwards; the repository working tree was left unchanged by the audit.
