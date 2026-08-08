//// Canonical, deterministic byte encoding of a Task for content-addressing.
////
//// Determinism contract: identical Task field values MUST produce identical
//// bytes, in every process, on every run. Therefore:
////   - fixed field order
////   - every variable-length value is length-prefixed (32-bit big-endian count)
////   - enums map to a fixed byte; Option to a tag byte
////   - Ints (bignum-safe) are encoded as length-prefixed decimal strings
////   - the relationship + labels lists are SORTED before encoding
////   - a leading VERSION byte lets us invalidate every hash if the encoding
////     ever changes (see ADR-0002 — canonical-serialization versioning)
////
//// content_hash is intentionally NOT encoded — it is derived from these bytes.

import bankai/types.{
  type RelationType, type Relationship, type Task, type TaskKind,
  type TaskStatus, Blocked, Blocks, Bug, CausedBy, Chore, Closed, Completed,
  ConditionalBlocks, Decision, DefaultTask, DiscoveredFrom, Duplicates, Epic,
  Feature, Gate, InProgress, Open, ParentChild, RelatesTo, RepliesTo, Supersedes,
  Tracks, Validates, WaitsFor, Wisp,
}
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/option.{type Option}
import gleam/order
import gleam/string

/// Bump if the encoding changes; it invalidates every prior content hash.
/// v2 (G3): added the `labels` list.
/// v4 (workflow controls): added `defer_until` and `closure_reason`.
/// v5 (parity Task 5): added explicit gate due/satisfaction state.
const canonical_version = 5

pub fn canonical_bytes(task: Task) -> BitArray {
  <<canonical_version:size(8)>>
  |> put_str(task.id)
  |> put_str(task.title)
  |> put_str(task.description)
  |> put_byte(status_code(task.status))
  |> put_option_str(task.assignee)
  |> put_int(task.priority)
  |> put_int(task.created_at)
  |> put_int(task.updated_at)
  |> put_relationships(task.relationships)
  |> put_labels(task.labels)
  |> put_byte(kind_code(task.kind))
  |> put_option_str(task.parent_id)
  |> put_option_int(task.defer_until)
  |> put_option_str(task.closure_reason)
  |> put_option_int(task.gate_due)
  |> put_byte(bool_code(task.gate_satisfied))
}

// --- segment builders ---

fn put_str(acc: BitArray, s: String) -> BitArray {
  let bytes = bit_array.from_string(s)
  let len = bit_array.byte_size(bytes)
  <<acc:bits, len:size(32), bytes:bits>>
}

fn put_byte(acc: BitArray, b: Int) -> BitArray {
  <<acc:bits, b:size(8)>>
}

fn put_int(acc: BitArray, n: Int) -> BitArray {
  // bignum-safe: canonical decimal string, length-prefixed.
  put_str(acc, int.to_string(n))
}

fn put_option_str(acc: BitArray, opt: Option(String)) -> BitArray {
  case opt {
    option.None -> <<acc:bits, 0:size(8)>>
    option.Some(s) -> put_str(<<acc:bits, 1:size(8)>>, s)
  }
}

fn put_option_int(acc: BitArray, opt: Option(Int)) -> BitArray {
  case opt {
    option.None -> <<acc:bits, 0:size(8)>>
    option.Some(value) -> put_int(<<acc:bits, 1:size(8)>>, value)
  }
}

fn put_relationships(acc: BitArray, rels: List(Relationship)) -> BitArray {
  // Sort for determinism by (relation_code, target_id).
  let sorted =
    list.sort(rels, by: fn(a, b) {
      case int.compare(relation_code(a.relation), relation_code(b.relation)) {
        order.Eq -> string.compare(a.target_id, b.target_id)
        other -> other
      }
    })

  let acc = put_int(acc, list.length(sorted))
  list.fold(sorted, acc, fn(a, rel) {
    a
    |> put_byte(relation_code(rel.relation))
    |> put_str(rel.target_id)
  })
}

fn put_labels(acc: BitArray, labels: List(String)) -> BitArray {
  // Sort for determinism (labels are an unordered set semantically).
  let sorted = list.sort(labels, by: string.compare)
  let acc = put_int(acc, list.length(sorted))
  list.fold(sorted, acc, fn(a, label) { put_str(a, label) })
}

// --- enum -> stable byte code ---

fn status_code(s: TaskStatus) -> Int {
  case s {
    Open -> 1
    InProgress -> 2
    Blocked -> 3
    Completed -> 4
    Closed -> 5
  }
}

fn relation_code(r: RelationType) -> Int {
  case r {
    Blocks -> 1
    RelatesTo -> 2
    Duplicates -> 3
    Supersedes -> 4
    RepliesTo -> 5
    ParentChild -> 6
    WaitsFor -> 7
    DiscoveredFrom -> 8
    Tracks -> 9
    CausedBy -> 10
    Validates -> 11
    ConditionalBlocks -> 12
  }
}

fn bool_code(value: Bool) -> Int {
  case value {
    True -> 1
    False -> 0
  }
}

fn kind_code(k: TaskKind) -> Int {
  case k {
    DefaultTask -> 1
    Bug -> 2
    Feature -> 3
    Epic -> 4
    Decision -> 5
    Chore -> 6
    Gate -> 7
    Wisp -> 8
  }
}
