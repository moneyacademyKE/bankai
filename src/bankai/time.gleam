//// Monotonic-ish timestamp for `updated_at` + task-id suffix.
////
//// NOTE on BUG-08: kept at native resolution (erlang:system_time/0) rather than
//// milliseconds. Switching to ms made the task-id suffix collide under rapid
//// sequential `create`s (two creates in the same millisecond share an id and
//// The proper fix is to DERIVE a short id from the content hash (bk-a3f8), which
//// requires `id` to leave canonical_bytes (a Task-model design change), tracked
//// as a follow-up. Native units keep ids collision-free.

///  silently merge) — a correctness regression worse than the 19-digit UX nit.
@external(erlang, "erlang", "system_time")
pub fn now() -> Int
