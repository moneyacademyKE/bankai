//// Pillar 2 — mobile rules: content-addressed, executable, sync-able.
////
//// A "rule" is a gleamunison S-expression source string. Its identity is the
//// SHA-256 of its source (gleamunison/identity.hash_bytes). Rules are stored
//// in a registry, gated by an allow-list, executed via gleamunison/repl, and
//// synced across registries by hash (identical sources dedupe cleanly).
////
//// SECURITY (per ADR-0003, layered defense in depth):
////   - Trust:      a rule runs only if its hash is explicitly approved; register
////                 != approve (registration is arrival, approval is trust).
////   - Capability: rules are pure — repl's eval surface exposes no file/net/proc
////                 builtins. Effectful rules require capability tokens (future).
////   - Resource:   every eval is bounded by a wall-clock timeout (default 1s).
////   - Isolation:  eval runs in an UNLINKED spawned process (a crash/loop can't
////                 reach the daemon handler); monitor-based instant crash
////                 detection + timeout-bounded, runaway killed. See `run_isolated`.

import gleam/bit_array
import gleam/dict.{type Dict}
import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/set.{type Set}
import gleamunison/identity
import gleamunison/repl

/// Default wall-clock budget for a single rule eval (ms). Generous for the
/// tiny predicate rules pillar 2 is built for; bounded so a pathological rule
/// can't hang the daemon. See ADR-0003.
pub const default_eval_timeout_ms = 1000

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

/// Register a rule. NOT auto-approved — call `approve` to make it executable.
/// (ADR-0003 trust layer: registration is arrival, approval is trust.)
pub fn register(
  reg: Registry,
  name: String,
  source: String,
) -> #(Registry, identity.Hash) {
  let hash = source_hash(source)
  let k = key(hash)
  let rule = Rule(name:, source:, hash:)
  let reg =
    Registry(rules: dict.insert(reg.rules, k, rule), approved: reg.approved)
  #(reg, hash)
}

pub fn lookup(reg: Registry, hash: identity.Hash) -> Result(Rule, Nil) {
  dict.get(reg.rules, key(hash))
}

type IsolatedOutcome {
  Replied(result: Result(String, String))
  Crashed
}

/// Run `work` in an ISOLATED, UNLINKED process bounded by a wall-clock timeout,
/// with MONITOR-based instant crash detection.
///
/// - Isolation: `spawn_unlinked` (NOT linked `spawn`) so a crash/exit in `work`
///   is contained — it cannot take down the caller (the daemon handler).
/// - Crash detection: the worker is `monitor`-ed. If it exits before replying,
///   the DOWN message wins the selector IMMEDIATELY (no waiting out the budget),
///   yielding a distinct "crashed" error — better than timeout-only detection.
/// - Bounded: `selector_receive(within)` returns Error(Nil) on timeout expiry
///   (a looping rule that neither replies nor crashes).
/// - Cleanup: on timeout the monitor is dropped and the runaway process killed.
///
/// See ADR-0003 (isolation + resource layers).
pub fn run_isolated(
  work: fn() -> Result(String, String),
  timeout_ms: Int,
) -> Result(String, String) {
  let reply = process.new_subject()
  let pid = process.spawn_unlinked(fn() { process.send(reply, work()) })
  let monitor = process.monitor(pid)
  let selector =
    process.new_selector()
    |> process.select_map(for: reply, mapping: fn(result) { Replied(result) })
    |> process.select_specific_monitor(monitor, fn(_) { Crashed })
  case process.selector_receive(from: selector, within: timeout_ms) {
    Ok(Replied(result)) -> {
      process.demonitor_process(monitor:)
      result
    }
    Ok(Crashed) -> Error("rule eval crashed (isolated process exited)")
    Error(Nil) -> {
      process.demonitor_process(monitor:)
      process.kill(pid)
      Error("rule eval timed out after " <> int.to_string(timeout_ms) <> "ms")
    }
  }
}

/// Execute an approved rule, isolated + timeout-bounded at the default budget.
pub fn eval(reg: Registry, hash: identity.Hash) -> Result(String, String) {
  eval_with_timeout(reg, hash, default_eval_timeout_ms)
}

/// Execute an approved rule with an explicit wall-clock budget (ms).
pub fn eval_with_timeout(
  reg: Registry,
  hash: identity.Hash,
  timeout_ms: Int,
) -> Result(String, String) {
  case lookup(reg, hash) {
    Error(Nil) -> Error("no such rule")
    Ok(rule) ->
      case set.contains(reg.approved, key(hash)) {
        False -> Error("rule not approved (allow-list denied)")
        True -> run_isolated(fn() { repl.eval_string(rule.source) }, timeout_ms)
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

/// Content-addressed sync: union two registries by rule hash (identical sources
/// dedupe — same hash). BUT approvals stay LOCAL — BUG-06 fix: the old code
/// `set.union`-ed approvals, letting a rule approved on ANY rig become
/// executable everywhere after merge, bypassing ADR-0003's trust layer
/// ("registration is arrival, approval is trust"). Sync propagates RULES (data),
/// never TRUST — each rig approves locally.
pub fn merge(a: Registry, b: Registry) -> Registry {
  let rules =
    dict.to_list(b.rules)
    |> list.fold(a.rules, fn(acc, pair) {
      let #(_, rule) = pair
      dict.insert(acc, key(rule.hash), rule)
    })
  Registry(rules:, approved: a.approved)
}

pub fn count(reg: Registry) -> Int {
  dict.size(reg.rules)
}
