//// Adoptions of gleamunison 3.21.0 that have no existing home.

import bankai/cli
import bankai/metrics_view
import gleam/json
import gleam/string
import gleamunison/metrics
import gleeunit/should

pub fn doctor_reports_metrics_snapshot_test() {
  metrics.counter("bankai.test.adopt", 1)
  let snap = json.to_string(metrics_view.snapshot())
  snap |> string.contains("bankai.test.adopt") |> should.be_true
}

pub fn llm_complete_without_a_key_is_loud_test() {
  let out = cli.run_in("/tmp/bankai_llm_test", ["llm", "complete", "ping"])
  out |> string.contains("\"error\"") |> should.be_true
  out |> string.contains("missing") |> should.be_true
}

pub fn llm_usage_is_loud_test() {
  let out = cli.run_in("/tmp/bankai_llm_test", ["llm"])
  out |> string.contains("usage: llm complete") |> should.be_true
}
