# ADR-0002: Canonical-serialization versioning

**Status:** Accepted
**Date:** 2026-08-03
**Resolves:** ADR-0001 open follow-up #1 (canonical-serialization versioning for `Task` → bytes).

## Context

A Task's identity is its `content_hash`: `SHA-256(canonical_bytes(task))` via
`gleamunison/identity.hash_bytes`. Because the hash **is** the address — it is
the store key, the `.bankai/tasks.jsonl` identity, the cross-rig sync identity,
and what agents reference with `bankai inspect <hash>` — the exact byte encoding
that produces the hash is load-bearing. Any silent change to that encoding
(adding a field, reordering fields, altering an enum→byte mapping, changing the
integer representation) would invalidate every existing address: stored hashes
would no longer match recomputed ones, tasks would become unaddressable, and Git
merges across rigs would fragment.

`canonical_bytes` (`src/bankai/canonical.gleam`) currently encodes a `Task` as:

```
<version:8>
<id len:32><id utf8>
<title len:32><title utf8>
<description len:32><description utf8>
<status:8>            // Open=1 InProgress=2 Blocked=3 Completed=4 Closed=5
<assignee tag:8> [<assignee len:32><assignee utf8>]   // tag 0=None, 1=Some
<priority len:32><priority decimal utf8>
<created_at len:32><created_at decimal utf8>
<updated_at len:32><updated_at decimal utf8>
<rel count len:32> <rel...>   // rels sorted by (relation_code, target_id);
                              // each = <relation:8> <target_id len:32><...utf8>
```

Integers are encoded as their decimal string (length-prefixed) so arbitrary-size
Gleam `Int` is exact and canonical. `content_hash` is **deliberately excluded**
from the encoding — a hash cannot meaningfully contain itself; verification
recomputes and compares (ADR-0001).

The leading `<version:8>` byte already exists (= `0x01`) but was undocumented.
This ADR makes the version contract explicit and governs how it evolves.

## Decision

### 1. The leading version byte is the canonical-format version, owned by this ADR.

- Current canonical-format version: **`0x01`**.
- `canonical_bytes` MUST emit the version byte first; `hash_bytes` hashes it as
  part of the content. The byte therefore participates in the content address —
  two encodings that differ only in version produce different hashes by design.
- The version byte is a *format* version, distinct from the `bankai` package
  version. A package release may ship without a format bump; a format bump is a
  release event (see §3).

### 2. A version bump is a content-address migration — treat it as such.

Changing the canonical encoding REQUIRES bumping the version byte. The
consequence is real and must be planned for:

- **Every existing task's `content_hash` changes.** Old hashes written to
  `.bankai/tasks.jsonl`, committed to Git, referenced by `bankai inspect`, or
  cached by agents become addresses into the *previous* format.
- **Mitigation:** ship a migration that, on first load under the new format,
  re-addresses every stored task (recompute `content_hash` under the new
  `canonical_bytes`) and records an `old_hash → new_hash` map in
  `.bankai/migrations.jsonl`. Agents that held old hashes re-resolve via that
  map. Old task *content* is never lost (only its address changes), because the
  fields round-trip through `serde` independently of the hash.
- A bump is a **major** bankai release and is announced alongside the migration
  tool. There is no in-place "transparent" rehashing without a version byte —
  silent rehashing is forbidden (it would break the integrity guarantee without
  a recorded reason).

### 3. Policy for evolving `canonical_bytes`

| Change | Action |
|---|---|
| Reorder fields, change a length-prefix width, change int/enum encoding | **Bump version byte**; ship migration. |
| Add a new `Task` field | **Bump version byte**; ship migration. Prefer making genuinely-optional new state live in a sidecar record rather than the hashed core. |
| Fix a determinism bug (e.g. unsorted relationships) | **Bump version byte**; ship migration. The pre-fix outputs were deterministic-but-wrong; they are still valid old-format addresses. |
| Change the version byte value itself | This IS the bump. |
| Rename a field / refactor internals **without** changing the byte layout | No bump required — only the byte layout participates in the address. |
| Add a new `TaskStatus`/`RelationType` variant | No bump required IF existing codes are unchanged and new variants take new codes (append-only enum). Adding a variant by renumbering existing codes **does** require a bump. |

### 4. Determinism contract (must hold for a given version)

Within one canonical-format version, `canonical_bytes` MUST be a pure,
deterministic function of the task's content fields:

- Relationships sorted by `(relation_code, target_id)` before encoding.
- Fixed field order (as documented above).
- Strings length-prefixed (big-endian 32-bit length) + UTF-8.
- Integers as canonical decimal strings (no leading zeros, no sign for
  non-negatives).
- Enums as fixed-width bytes with stable, append-only codes.

The `ast_bridge` determinism test (`identical→same hash`, `mutation→different
hash`, relationship-order-independent, idempotent rehash) **pins** the current
encoding: any change that alters bytes without bumping the version will fail it.
That test is the canary for an accidental encoding change.

## Consequences

**Positive**
- Content addresses are stable and trustworthy for the lifetime of a
  canonical-format version; integrity verification (recompute ↔ stored) holds.
- Format evolution is possible without ambiguity, with a documented, tooled
  migration path and a recorded `old_hash → new_hash` history.
- The determinism test enforces the contract in CI.

**Negative / costs**
- A version bump is a coordinated release + migration, not a silent change —
  deliberately heavier, which is the point (addresses are sacred).
- The migration map adds a small migration-time artifact
  (`.bankai/migrations.jsonl`) until all agents have re-resolved.
- Cross-rig sync spanning two format versions requires both sides to honour the
  migration map; pre-migration rigs see post-migration hashes as "unknown"
  until they migrate. Acceptable: format bumps are rare, coordinated events.

## Alternatives considered

**No version byte / opaque encoding.** Rejected: a content-addressed system
cannot silently change its hash inputs. Without a version byte there is no way
to distinguish "same task, new code" from "different task," and integrity
verification becomes meaningless.

**Include `bankai` package version instead of a format byte.** Rejected: package
version changes far more often than the canonical format and would force
gratuitous migrations. The format version is its own, slower-moving axis.

**Self-describing encoding (e.g. tagged TLV / CBOR) instead of positional.**
Deferred: would make the encoding more resilient to additive change (a new
field could be added without a bump in some schemes), but adds parsing
complexity and is not warranted while the `Task` shape is stable. Revisit if
hashed-field churn grows; a bump to a self-describing format would itself be a
version `0x02` migration.

## Verification

- The version byte (`0x01`) is the first byte of `canonical_bytes(task)` for all
  tasks — asserted by reading the leading byte in the canonical test.
- The `ast_bridge` determinism test pins the byte layout for version `0x01`.
- A future migration test will assert that a version bump + rehash produces a
  populated `.bankai/migrations.jsonl` and that post-migration `inspect` of an
  old hash re-resolves to the new one.
