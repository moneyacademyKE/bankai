import gleeunit
import gleeunit/should
import gleam/string
import gleamunison/identity
import bankai/rules/registry

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

pub fn eval_approved_rule_runs_in_gleamunison_test() {
  let #(reg, h) = registry.register(registry.new(), "forty-two", "42")
  let result = registry.eval(reg, h)

  result
  |> should.be_ok
  |> string.contains("42")
  |> should.be_true
}

pub fn revoke_blocks_eval_test() {
  let #(reg, h) = registry.register(registry.new(), "forty-two", "42")
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
  let merged = registry.merge(a, b)

  registry.count(merged)
  |> should.equal(2)
  // ruleB from b is now present + approved in the merged registry.
  registry.is_approved(merged, hb)
  |> should.be_true
  registry.eval(merged, hb)
  |> should.be_ok
}
