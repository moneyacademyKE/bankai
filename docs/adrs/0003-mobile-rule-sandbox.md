# ADR-0003: Durable mobile-rule sandbox

**Status:** Accepted and implemented

**Date:** 2026-08-03

**Last reconciled:** 2026-08-12

**Resolves:** ADR-0001 follow-up #2 — mobile-rule execution security model

## Context

Bankai’s second pillar is mobile code: a rule is Gleamunison S-expression source, content-addressed by SHA-256, evaluated through `gleamunison/repl`, and useful as a validation predicate or graph query. This is executable untrusted input. Treating registration as permission or running the evaluator in the daemon process would be reckless.

A rule can be malformed, can loop, can crash an immature evaluator path, or can become more dangerous if the evaluator later gains ambient capabilities. Task state and the daemon must remain safe regardless.

## Decision

Rules are durable local artifacts with a separate, local trust decision. They are never task authority.

| Concern | Durable location | Rule |
|---|---|---|
| Source artifact | Mnesia `bankai_rule_artifacts_v1` | Content hash identifies source; registration is idempotent and never grants execution permission. |
| Local approval | Mnesia `bankai_rule_approvals_v1` | Approval/revocation is per workspace and separate from source arrival. |
| Evaluation audit | Mnesia `bankai_rule_audits_v1` | Every success and failure has an ordered audit record. |
| Task context | One immutable JSON serialization of an optional current task | Evaluator receives data only; it gets no Mnesia handle, task mutation function, file, network, or process capability. |

The operator-facing lifecycle is:

    bankai rule register <name> <source>
    bankai rule list
    bankai rule show <hash>
    bankai rule approve <hash>
    bankai rule revoke <hash>
    bankai rule eval <hash> [--caller <name>] [--task <task-id>]
    bankai rule audit [hash]

The daemon socket exposes equivalent methods (`rule_register`, `rule_list`, `rule_show`, `rule_approve`, `rule_revoke`, `rule_eval`, and `rule_audit`) and Bankai MCP exposes matching tools. Results keep the project’s stable JSON-envelope contract.

## Security model

### 1. Trust: explicit local allow-list

A source can be stored without being executable. `register` records an artifact as **unapproved**. `approve` is a local operator action. `revoke` immediately denies later evaluation. The evaluator checks approval immediately before execution and fails closed with `rule not approved (allow-list denied)`.

Artifacts are intentionally local-only. Peer replication does not transport rule artifacts or approval rows. If source exchange is added later, arrival must remain unapproved and cannot inherit trust from another workspace or rig.

### 2. Capability: pure evaluation only

Rules evaluate as a unary pure function over an immutable JSON text input. The constructed expression quotes the input, preventing task data from escaping into code syntax. No file, network, process, database, or daemon capability is supplied to the evaluator.

A future effectful rule feature requires a separate ADR defining explicit, auditable capability tokens. Ambient authority is prohibited.

### 3. Resource bounds: timeout, heap, reductions, and artifact size

The service limits rule source to 16,384 characters and names to 256 characters. Every evaluation runs with three independent worker limits:

- wall-clock timeout: `1,000 ms`;
- process heap: `262,144` BEAM words (roughly 2 MiB on a 64-bit VM), enforced with `spawn_opt` `max_heap_size` and kill-on-exceed;
- reductions: `250,000`, sampled every millisecond and killed on exceed.

Timeout, heap exhaustion, and reduction exhaustion are distinct audited errors. These bounds are deliberately proportional to small predicate/annotation rules; materially more expressive workloads require a separate policy decision rather than silently increasing them.

### 4. Isolation: unlinked monitored worker

`registry.run_isolated` evaluates in a spawned **unlinked** process. The caller monitors that worker and races its reply against a monitor-down signal and the timeout. Therefore:

- an evaluator crash produces a bounded `crashed` error rather than taking down the socket handler;
- a non-replying loop times out and is killed;
- malformed source is contained in the worker;
- no rule evaluation can mutate task state because the evaluator has no mutation path.

### 5. Audit: ordered evidence

Every evaluation attempt appends a durable audit record. Each record contains:

- monotonic sequence;
- rule hash and caller;
- immutable input hash;
- optional task ID and the task content hash observed;
- elapsed duration in nanoseconds;
- `ok` or `error` outcome and returned text.

Audit ordering uses an append sequence rather than wall-clock ordering, so replay/debugging output is deterministic.

## Consequences

### Positive

- Rules survive daemon restart as data, while permission and audit survive separately.
- A registration does not become execution merely because it arrived.
- Unapproved and revoked hashes fail closed.
- Rule evaluation cannot become a second task writer or bypass Mnesia compare-and-swap.
- Crashing, malformed, and timing-out rules are contained while leaving the daemon and task history alive.
- MCP, CLI, and socket clients use one command shape rather than inventing separate rule semantics.

### Costs and limits

- Every evaluation pays the cost of process spawn, monitoring, input serialization, and audit persistence.
- Rule source is portable content, but approval is intentionally not portable. That friction is security, not an unfinished sync feature.
- Rules currently observe only one optional task snapshot. They do not query arbitrary board state or authorize transitions.
- The heap cap is hard; the reduction cap is cooperative sampling at a 1 ms interval, so a worker can overshoot modestly before termination. This is bounded policy, not instruction-level determinism.

## Alternatives rejected

### In-memory registry only

Rejected. It loses source, approval, and audit across daemon restart and makes a product claim impossible.

### Registration auto-approves

Rejected. Arrival and trust are different things. Merging them turns any source submitter into an executor.

### Rule writes task state directly

Rejected. That would create hidden mutation authority alongside `daemon_store` and Mnesia transactions. Rules remain predicates; command semantics remain explicit data and code in Bankai’s daemon.

### Sync approvals between rigs

Rejected. Trust is local policy. A remote approval cannot authorize execution here.

### Separate VM/node now

Deferred. An isolated BEAM worker with no ambient effects, monitor crash detection, and timeout is the current proportional boundary. A distinct sandbox node becomes appropriate if capabilities or attack surface materially grow.

## Verification

`test/rule_service_test.gleam` covers durable source/approval/audit recovery, unapproved and revoked denial, malformed source containment, immutable task-view evaluation without task mutation, and socket envelope behavior. Existing `rules_test` covers isolated crash survival and timeout behavior.

At the 2026-08-12 reconciliation point, `gleam test` reports **182 passing tests**. Test output intentionally includes a crash report from the isolated worker crash-survival test; that report is the evidence that the worker dies without taking the caller down.

## Follow-up hardening

- Define capability-token semantics before adding effects.
- Add signed source provenance only if rule exchange is introduced; local approval remains mandatory regardless.
- Re-measure and explicitly revise budgets only if real predicate workloads exceed them.
