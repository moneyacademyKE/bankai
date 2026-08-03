# ADR-0003: Mobile-rule execution sandbox (pillar 2 security model)

**Status:** Accepted
**Date:** 2026-08-03
**Resolves:** ADR-0001 follow-up #2 (mobile-rule execution sandbox / security model)

## Context

Pillar 2 of bankai (ADR-0001) is **mobile code by design**: one agent defines a
validation rule or graph predicate as a gleamunison S-expression, content-addresses
it (SHA-256 of the source via `gleamunison/identity.hash_bytes`), syncs it to other
agents in the mesh, and those agents **execute** it via `gleamunison/repl.eval_string`.

That is remote code execution. The security model is not optional — it is the
difference between "agents share pure predicates" and "a compromised agent ships a
rule that takes down the mesh."

### Threat model

| Asset | At risk from a malicious/buggy rule |
|---|---|
| The daemon process (holds the store + the JSON-RPC socket) | A rule that loops or allocates unboundedly can **hang** the daemon (eval is currently synchronous in the caller). |
| The workspace (`.bankai/tasks.jsonl`, task data) | A rule that can perform I/O could read/corrupt task state. |
| The host (filesystem, network) | A rule with effectful builtins could exfiltrate or mutate host state. |
| The eval runtime itself | gleamunison's eval/compile path is young (a `erl_crash.dump` was observed during the daemon build); a malformed rule can trigger an eval **crash**. |

The adversary is a compromised or merely buggy agent in the mesh. Note that even
**non-malicious** input matters: a rule with an infinite loop or huge allocation
exhausts resources regardless of intent.

### Current implementation status (be honest about the gap)

As of this ADR, `bankai/rules/registry.gleam#eval` does this:

```gleam
case set.contains(reg.approved, key(hash)) {
  False -> Error("rule not approved (allow-list denied)")
  True -> repl.eval_string(rule.source)   // synchronous, in the caller's process
}
```

- **Trust:** allow-list only. `register` **auto-approves**, so registration and
  approval are currently conflated — anyone who can register can execute.
- **Capability:** `repl.eval_string`'s S-expression surface has **no effectful
  builtins today** (no file/network/process; `define` is unsupported), so the
  capability layer is satisfied *vacuously* for now. The risk is that the surface
  **grows** as rules need real capabilities.
- **Resource bounds:** none. A pathological approved rule runs to completion or
  forever.
- **Isolation:** none. A rule crash or loop takes the daemon with it.

The layered model below is the **committed target**; layers 3-4 are not yet landed.
The required-hardening follow-up implements them.

## Decision

A **defense-in-depth** sandbox: five layers, each independently necessary. No
single layer is sufficient.

### Layer 1 — Trust (who may run)

A rule executes **only if its content hash is in the allow-list.** Approval is an
explicit operator action, **separate from registration.** (v1 keeps the allow-list
as the trust gate; signature-based trust is a v2 follow-up, not the baseline.)

> Behavior change from current: `register` must **stop auto-approving**. A rule is
> registered (stored, addressable, sync-able) but does not execute until `approve`
> is called. This is the headline hardening item.

### Layer 2 — Capability (what a rule may do)

**Pillar-2 rules are pure by policy — no side effects.** The eval surface exposed to
rules must **never** include ambient file/network/process builtins. If a rule
genuinely needs an effect (e.g. "inspect this task"), it is granted via an explicit,
audited **capability token** passed as an argument — never via global builtins.

For MVP this is already true (the surface is literal/constructor-only). This ADR
makes it a **hard rule**: any future growth of the eval surface that adds effects
must route them through capability tokens, and is itself a follow-up ADR.

### Layer 3 — Resource bounds (how long / how much)

Every rule eval runs with:

- a **wall-clock timeout** (default 1000 ms), and
- a **reduction / call budget** (BEAM reductions) as a CPU bound independent of
  wall-clock.

On timeout or budget exhaustion, the eval is killed and returns a bounded error
(`Error("rule timed out")` / `Error("rule exceeded reduction budget")`). This is
what stops a pathological-but-approved rule from hanging the daemon.

> Residual risk (documented): BEAM does not cheaply bound a single process's **heap
> growth**. A memory bomb is killed only when the wall-clock timer fires, not the
> instant it over-allocates. A hard per-process `max_heap_size` kill is a follow-up;
> until then the timeout is the bound.

### Layer 4 — Isolation (where it runs)

Rule eval runs in a **dedicated, spawned, monitored process** — never in the
daemon's accept loop and never in the caller's process. A crash, exit, or timeout
in a rule kills **only** that transient process; the daemon survives.

This reuses the **per-connection isolation pattern already proven in the socket
layer** (`bankai/socket.gleam` spawns a fresh process per connection so a malformed
line can't take down the accept loop). The same `process.spawn` + monitor discipline
applies to rule eval.

### Layer 5 — Audit (observability)

Every execution is logged: **rule hash, origin/caller, duration, result or error**.
Malicious or pathological rules are visible, not silent.

## Consequences

**Positive**
- A compromised agent's rule is contained: it can't hang the daemon (timeout +
  isolation), can't exfiltrate via ambient builtins (capability policy), and can't
  run without explicit approval (allow-list).
- bankai's fault-tolerance NFR (the supervisor survives; the store is durable)
  holds even under adversarial rule input.
- The hardening reuses an existing, tested isolation pattern — no new mechanism,
  just applied to rule eval.

**Negative / cost**
- The spawn + monitor + timeout wrapper adds per-eval latency (a process spawn) and
  module complexity.
- Capability-token plumbing is real future work the moment a rule needs an effect.
- Splitting `register` from `approve` is a behavior change that touches the registry
  API and its tests.
- Residual memory-bomb risk until a hard heap limit lands.

**Neutral**
- Rules remain pure functions. The sandbox restricts **how** they run, not **what**
  they can express — pillar 2's value (mobile, content-addressed, sync-able
  predicates) is preserved.

## Alternatives considered

**Allow-list only (current MVP).** Insufficient as the sole control: a
pathological-but-approved rule (infinite loop / large allocation) hangs the daemon
synchronously. Kept as **layer 1**, rejected as the *only* layer.

**Signature-based trust (content signing).** Sign each rule with the origin agent's
key; verify the signature on sync before it's even eligible for approval. Stronger
origin authentication than a bare allow-list, but heavier (key distribution,
verification). Layered in as a **v2 follow-up**, not the baseline.

**Separate sandbox runtime / isolated BEAM node / WASM.** Run rules in a fully
isolated runtime with no host access at all — the strongest containment. Heavy
plumbing (a second node, serialization across it). Deferred: the in-process
spawn + timeout + capability-policy is the MVP; a separate sandbox node is the
documented escalation if the eval surface ever grows genuinely effectful.

**No execution — treat rules as data only.** Safest, but discards pillar 2's entire
premise (mobile *executable* rules). Rejected on the same grounds as ADR-0001's
Option A — it abandons the project's novelty.

## Verification / follow-up

**Required hardening — IMPLEMENTED (45 tests green):**

1. ✅ `registry.eval` runs `repl.eval_string` in a spawned, **unlinked** process
   bounded by a wall-clock timeout (default 1s). On timeout the runaway is killed.
2. ✅ **Monitor-based instant crash detection:** the worker is `monitor`-ed, and a
   `Selector` races the reply against the DOWN message. A crash wins instantly
   (distinct `"crashed"` error) rather than waiting out the budget. This upgrades
   the original "timeout-only" plan; a looping rule that neither replies nor
   crashes still hits the timeout.
3. ✅ `register` no longer auto-approves — execution requires an explicit `approve`.
4. ✅ Tests: a slow rule is killed at the budget (`"timed out"`); a panicking rule
   returns `"crashed"` instantly without taking down the caller; an unapproved
   rule is denied even after registration.

**Longer-term (still open):**
- A reduction / call budget in addition to wall-clock.
- A per-process `max_heap_size` kill to close the memory-bomb residual.
- Capability tokens for effectful rules (+ a follow-up ADR defining the token model).
- Signature-based trust on sync.

This ADR resolves ADR-0001 follow-up #2. The hardening above is landed, not
aspirational — see `src/bankai/rules/registry.gleam#run_isolated`.
