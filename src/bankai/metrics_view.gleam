//// Read side for gleamunison/metrics. The writer lives in the dependency
//// (ETS table `gleamunison_metrics`). This module only reads it, so doctor
//// can show counters without bankai owning a second metrics store.

import gleam/json

@external(erlang, "bankai_metrics_ffi", "snapshot")
fn snapshot_rows() -> List(String)

/// Snapshot of recorded counters, gauges, and histogram samples.
/// Empty when nothing has been recorded in this VM.
pub fn snapshot() -> json.Json {
  json.array(snapshot_rows(), of: json.string)
}
