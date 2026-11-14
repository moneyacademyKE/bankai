import bankai/daemon_store
import bankai/mnesia_store
import gleeunit/should

@external(erlang, "bankai_ready_claim_test_ffi", "race")
fn race(workspace: String) -> Int

pub fn concurrent_claim_next_consumes_distinct_ready_heads_test() {
  let ws = "/tmp/bankai_claim_next_transaction_test"
  let _ = should.be_ok(mnesia_store.init(ws))
  let _ = should.be_ok(mnesia_store.reset_workspace_for_test(ws))
  let _ = should.be_ok(daemon_store.boot(ws))
  let _ = should.be_ok(daemon_store.create(ws, "Concurrent A", []))
  let _ = should.be_ok(daemon_store.create(ws, "Concurrent B", []))
  race(ws) |> should.equal(2)
  let remaining = daemon_store.claim_next_ready(ws, [])
  should.be_error(remaining)
}
