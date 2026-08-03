import bankai/rules/registry
import gleam/erlang/process
import gleam/string
import gleamunison/identity
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

pub fn register_returns_stable_hash_test() {
  let #(reg, h1) = registry.register(registry.new(), "forty-two", "42")
  let #(_, h2) = registry.register(registry.new(), "forty-two", "42")
  identity.hash_equal(h1, h2)
  |> should.be_true
  registry.count(reg)
  |> should.equal(1)
}

pub fn different_sources_get_different_hashes_test() {
  let #(_, h1) = registry.register(registry.new(), "a", "42")
  let #(_, h2) = registry.register(registry.new(), "b", "99")
  identity.hash_equal(h1, h2)
  |> should.be_false
}

/// ADR-0003 trust layer: register does NOT auto-approve — eval is denied until
/// an explicit `approve`.
pub fn eval_denied_until_approved_test() {
  let #(reg, h) = registry.register(registry.new(), "forty-two", "42")
  // unapproved -> denied
  registry.eval(reg, h)
  |> should.be_error
  let reg = registry.approve(reg, h)
  // approved -> runs in gleamunison
  registry.eval(reg, h)
  |> should.be_ok
  |> string.contains("42")
  |> should.be_true
}

pub fn revoke_blocks_eval_test() {
  let #(reg, h) = registry.register(registry.new(), "forty-two", "42")
  let reg = registry.approve(reg, h)
  registry.eval(reg, h)
  |> should.be_ok
  let reg = registry.revoke(reg, h)
  registry.eval(reg, h)
  |> should.be_error
  registry.is_approved(reg, h)
  |> should.be_false
}

pub fn eval_unknown_hash_errors_test() {
  registry.eval(registry.new(), identity.hash_bytes(<<>>))
  |> should.be_error
}

pub fn merge_unions_registries_by_hash_test() {
  let #(a, _ha) = registry.register(registry.new(), "ruleA", "42")
  let #(b, hb) = registry.register(registry.new(), "ruleB", "99")
  let b = registry.approve(b, hb)
  let merged = registry.merge(a, b)

  registry.count(merged)
  |> should.equal(2)
  // ruleB from b is now present + approved in the merged registry.
  registry.is_approved(merged, hb)
  |> should.be_true
  registry.eval(merged, hb)
  |> should.be_ok
}

/// ADR-0003 resource layer: a rule whose eval overruns the budget is killed and
/// reported as an error — it cannot hang the daemon.
pub fn run_isolated_times_out_test() {
  let slow = fn() {
    process.sleep(500)
    Ok("late")
  }
  let result = registry.run_isolated(slow, 50)
  let msg = should.be_error(result)
  should.be_true(string.contains(msg, "timed out"))
}

/// ADR-0003 isolation layer: a rule whose eval CRASHES is contained — it returns
/// an error (does not hang), and crucially does NOT take down this test process
/// (the spawned eval is unlinked). Reaching the assertions proves containment.
pub fn run_isolated_survives_crash_test() {
  let boom = fn() { panic as "rule eval blew up" }
  let result = registry.run_isolated(boom, 200)
  // Crash is now detected INSTANTLY via the monitor (DOWN message), not by
  // waiting out the budget — so the error says "crashed", not "timed out".
  let msg = should.be_error(result)
  should.be_true(string.contains(msg, "crashed"))
}
