//// Monotonic-ish timestamp for `updated_at`. Units are Erlang native system
//// time; we only need an increasing integer for state versioning, not wall-clock.

@external(erlang, "erlang", "system_time")
pub fn now() -> Int
