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
import gleam/list
import gleam/result
import gleam/set.{type Set}
import gleam/string
import gleamunison/identity
import gleamunison/repl

/// Default wall-clock budget for a single rule eval (ms).
pub const default_eval_timeout_ms = 1000

/// Hard worker heap cap in BEAM words (~2 MiB on a 64-bit VM).
pub const default_eval_max_heap_words = 262_144

/// Maximum reductions consumed by one rule evaluation.
pub const default_eval_reduction_limit = 250_000

@external(erlang, "bankai_rule_worker_ffi", "run_bounded")
fn ffi_run_bounded(
  work: fn() -> Result(String, String),
  timeout_ms: Int,
  max_heap_words: Int,
  reduction_limit: Int,
) -> Result(Result(String, String), String)

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

pub fn source_hash_text(source: String) -> String {
  source_hash(source)
  |> identity.hash_to_debug_string()
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

/// Execute pure work in an unlinked worker bounded independently by wall-clock,
/// heap words, and BEAM reductions. The Erlang boundary owns process monitoring
/// so a heap kill cannot be mistaken for a normal evaluator result.
pub fn run_isolated(
  work: fn() -> Result(String, String),
  timeout_ms: Int,
) -> Result(String, String) {
  run_bounded(
    work,
    timeout_ms,
    default_eval_max_heap_words,
    default_eval_reduction_limit,
  )
}

pub fn run_bounded(
  work: fn() -> Result(String, String),
  timeout_ms: Int,
  max_heap_words: Int,
  reduction_limit: Int,
) -> Result(String, String) {
  ffi_run_bounded(work, timeout_ms, max_heap_words, reduction_limit)
  |> result.flatten
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

/// Evaluate a source artifact as a pure unary lambda over an immutable JSON
/// text view. The quoted argument prevents task-view data escaping into syntax;
/// this worker has no task, file, network, or process authority.
pub fn eval_source_with_input(
  source: String,
  input_json: String,
  timeout_ms: Int,
) -> Result(String, String) {
  let expression = "(" <> source <> " " <> quote_text(input_json) <> ")"
  run_isolated(fn() { repl.eval_string(expression) }, timeout_ms)
}

fn quote_text(text: String) -> String {
  let escaped =
    text
    |> string.replace(each: "\\", with: "\\\\")
    |> string.replace(each: "\"", with: "\\\"")
    |> string.replace(each: "\n", with: "\\n")
    |> string.replace(each: "\r", with: "\\r")
  "\"" <> escaped <> "\""
}
