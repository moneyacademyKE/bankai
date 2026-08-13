//// Monotonic-ish timestamp for `updated_at` + task-id suffix.
////
//// Bankai persists nanoseconds because task IDs need native-resolution
//// uniqueness. Calendar durations must use `day_ns`, never a bare 86_400.

pub const second_ns = 1_000_000_000

pub const day_ns = 86_400_000_000_000

@external(erlang, "erlang", "system_time")
pub fn now() -> Int
