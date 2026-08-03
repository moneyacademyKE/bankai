//// Pillar 2 — mobile rules: content-addressed, executable, sync-able.
////
//// A "rule" is a gleamunison S-expression source string. Its identity is the
//// SHA-256 of its source (gleamunison/identity.hash_bytes). Rules are stored
//// in a registry, gated by an allow-list, executed via gleamunison/repl, and
//// synced across registries by hash (identical sources dedupe cleanly).
////
//// SECURITY (v1): execution is allow-list-gated — a rule must be approved
//// before eval. Full gleamunison/sync of compiled definitions across BEAM
//// nodes + a sandbox is a follow-up ADR (see ADR-0001 follow-ups).

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/list
import gleam/set.{type Set}
import gleamunison/identity
import gleamunison/repl

pub type Rule {
  Rule(name: String, source: String, hash: identity.Hash)
}

pub opaque type Registry {
  Registry(rules: Dict(String, Rule), approved: Set(String))
}

pub fn new() -> Registry {
  Registry(rules: dict.new(), approved: set.new())
}

/// Content address of a rule source = SHA-256 of the source bytes.
pub fn source_hash(source: String) -> identity.Hash {
  identity.hash_bytes(bit_array.from_string(source))
}

fn key(h: identity.Hash) -> String {
  identity.hash_to_debug_string(h)
}

/// Register a rule (auto-approved by default; revoke to gate it).
pub fn register(
  reg: Registry,
  name: String,
  source: String,
) -> #(Registry, identity.Hash) {
  let hash = source_hash(source)
  let k = key(hash)
  let rule = Rule(name:, source:, hash:)
  let reg =
    Registry(
      rules: dict.insert(reg.rules, k, rule),
      approved: set.insert(reg.approved, k),
    )
  #(reg, hash)
}

pub fn lookup(reg: Registry, hash: identity.Hash) -> Result(Rule, Nil) {
  dict.get(reg.rules, key(hash))
}

/// Execute an approved rule via gleamunison's eval endpoint.
pub fn eval(reg: Registry, hash: identity.Hash) -> Result(String, String) {
  case lookup(reg, hash) {
    Error(Nil) -> Error("no such rule")
    Ok(rule) ->
      case set.contains(reg.approved, key(hash)) {
        False -> Error("rule not approved (allow-list denied)")
        True -> repl.eval_string(rule.source)
      }
  }
}

pub fn approve(reg: Registry, hash: identity.Hash) -> Registry {
  Registry(..reg, approved: set.insert(reg.approved, key(hash)))
}

pub fn revoke(reg: Registry, hash: identity.Hash) -> Registry {
  Registry(..reg, approved: set.delete(reg.approved, key(hash)))
}

pub fn is_approved(reg: Registry, hash: identity.Hash) -> Bool {
  set.contains(reg.approved, key(hash))
}

/// Content-addressed sync: union two registries by rule hash. Identical sources
/// dedupe (same hash); approved sets union.
pub fn merge(a: Registry, b: Registry) -> Registry {
  let rules =
    dict.to_list(b.rules)
    |> list.fold(a.rules, fn(acc, pair) {
      let #(_, rule) = pair
      dict.insert(acc, key(rule.hash), rule)
    })
  Registry(rules:, approved: set.union(a.approved, b.approved))
}

pub fn count(reg: Registry) -> Int {
  dict.size(reg.rules)
}
