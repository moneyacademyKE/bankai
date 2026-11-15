import bankai/daemon_store
import bankai/mnesia_store
import bankai/projections
import gleeunit/should

pub fn runtime_status_compares_against_committed_authority_test() {
  let workspace = "/tmp/bankai_runtime_freshness_regression"
  mnesia_store.init(workspace) |> should.be_ok
  mnesia_store.reset_workspace_for_test(workspace) |> should.be_ok
  projections.start_runtime(workspace) |> should.be_ok
  daemon_store.create(workspace, "after runtime snapshot", []) |> should.be_ok
  let stale = projections.runtime_status(workspace) |> should.be_ok
  stale.healthy |> should.be_false
  stale.high_watermark |> should.equal(0)
  stale.history_lag |> should.equal(1)
  stale.text_lag |> should.equal(1)
  stale.vector_lag |> should.equal(1)
  projections.ensure_runtime(workspace) |> should.be_ok
  let fresh = projections.runtime_status(workspace) |> should.be_ok
  fresh.healthy |> should.be_true
  fresh.history_lag |> should.equal(0)
}
