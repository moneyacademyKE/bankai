//// The gleamunison binding bridge for Task content-addressing (pillar 1).
////
//// `task_hash` = SHA-256 over the canonical byte encoding. No gleamunison
//// evaluation happens here (that's pillar 2, src/bankai/rules). This is the
//// cheap, frequent path that meets the sub-5ms NFR.

import bankai/canonical
import bankai/types.{type Task, Task}
import gleam/string
import gleamunison/identity.{
  type Hash, hash_bytes, hash_equal, hash_to_debug_string,
}

/// Content-address a Task: SHA-256 over its canonical byte encoding.
pub fn task_hash(task: Task) -> Hash {
  // canonical_bytes excludes content_hash, so this is well-defined and
  // independent of any stale value currently stored in task.content_hash.
  hash_bytes(canonical.canonical_bytes(task))
}

/// Set a Task's content_hash to the hash of its current content fields.
/// Idempotent: rehash(rehash(t)).content_hash == rehash(t).content_hash.
pub fn rehash(task: Task) -> Task {
  Task(..task, content_hash: task_hash(task))
}

/// Empty/placeholder hash — used to seed a draft Task before rehash.
pub fn empty_hash() -> Hash {
  hash_bytes(<<>>)
}

/// Verify a stored Task: its content_hash must equal the hash of its fields.
/// Tamper detection: any field edit without rehash makes this false.
pub fn content_hash_valid(task: Task) -> Bool {
  hash_equal(task_hash(task), task.content_hash)
}

/// Verify a stored Task at an authority boundary. A task's claimed identity
/// must be the hash of its canonical content; callers must reject mismatches
/// rather than silently assigning a new identity to untrusted data.
pub fn validate(task: Task) -> Result(Task, String) {
  case content_hash_valid(task) {
    True -> Ok(task)
    False ->
      Error(
        "task content_hash does not match canonical task content for id "
        <> task.id,
      )
  }
}

/// Short human-readable id in beads style: "bk-" + first 4 hex chars.
pub fn task_short_id(task: Task) -> String {
  "bk-" <> string.slice(hash_to_debug_string(task_hash(task)), 0, 4)
}
