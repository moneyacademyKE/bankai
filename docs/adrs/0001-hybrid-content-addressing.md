# ADR-0001: Hybrid Content-Addressing — SHA-256 for task state, Unison AST for mobile rules

**Status:** Accepted
**Date:** 2026-08-03
**Decider:** moe (@designpoa)
**Supersedes:** —

## Context

`bankai` is a content-addressed task memory graph for distributed AI agent swarms, built in
**Gleam on the BEAM VM** (`gleam_otp`) and backed by **gleamunison** (`moneyacademyKE/gleamunison`).
The product surface is modeled on **beads** (`gastownhall/beads`, a Go/Dolt graph issue tracker):
hash-IDed tasks (`bk-a3f8`), dependency relations, `ready/create/update/inspect`, and
3-way-mergeable sync across rigs.

The original master spec set two hard constraints and one architectural claim that are in tension:

- **NFR (perf):** single-shot CLI operations must be sub-5 ms.
- **NFR (concurrency safety):** relation adds must be rejected if they would create a cycle.
- **Claim:** every task mutation flows through a Unison AST term, evaluated via
  `gleamunison/evaluator.eval()`.

Three problems surfaced when the spec was checked against the *real* source of gleamunison,
gleamdb, and beads.

### Problem 1 — the spec's `gleamunison` API is partly fictional

Verified against `moneyacademyKE/gleamunison` source:

| Spec assumed | Reality |
|---|---|
| `gleamunison/ast.{Term, Hash}` | `Term` ✓ real; **`Hash` lives in `gleamunison/identity`, not `ast`** |
| `gleamunison/runtime` | **No such module** |
| `gleamunison/evaluator.eval()` → `Ok(ast.Boolean(true))` | **Invented** — no `evaluator` module, no `Boolean` variant |
| `ast.call / ast.var / ast.from_task / ast.from_hash_list` | **Invented** — real `Term` is algebraic: `Apply(fn, arg)`, `RefTo(DefinitionRef)`, `Int`, `Text(BitArray)`, `Lambda`, `Match`, `Construct` |
| `identity.hash_bytes(BitArray) -> Hash` | ✓ **real** (SHA-256) |

Code scaffolded against the spec's assumed API would not compile. This ADR is the correction.

### Problem 2 — the spec complects data identity with code mobility

"Content-addressing" is asked to do two genuinely different jobs:

- **(a) Give a Task a tamper-proof, deterministic identity** so its state history forms a hash
  chain. This is a *data* problem.
- **(b) Let an agent define a validation rule or graph predicate, ship it to other agents by hash,
  and have them execute it without recompiling.** This is a *code mobility* problem.

The spec routes **both** through `ApplyTransition(transition_fn_ast: Term)` — a Unison
parse → elaborate → compile → load → eval on every mutation. That satisfies (b) but is wildly
overkill for (a), and it **directly violates the sub-5 ms NFR** (parse + elaborate + compile +
dynamic-load + eval is tens of ms; cold VM is worse — the project's own gap analysis flags
gleamunison cold starts, and the dogfood tree contains an `erl_crash.dump`).

### Problem 3 — the spec rebuilds things that already exist, tested

| bankai phase | Already built (same author) |
|---|---|
| ETS/Mnesia content store by hash | `gleamunison/storage.mnesia(table)` / `dets(path)` + `codebase` |
| OTP task actor (`gleam_otp`) | **`aarondb/transactor/{runtime,apply,messages}`** |
| Graph: cycle-detect + topological sort | **`aarondb/algo/graph`** — `cycle_detect`, `topological_sort`, `reachable`, `connected_components` (tested) |
| Sync / 3-way merge across rigs | **`gleamunison/sync`** — `pull_sync` / `push_sync` |
| JSON-RPC socket server | `gleamunison/http.start_server(port)` |

## Decision

**Split the two jobs. Address the data cheaply; address the code with the real Unison machinery.**

### Pillar 1 — Task state identity (frequent path)

A `Task` is a plain Gleam struct. Content-addressing is canonical-serialization →
`identity.hash_bytes` (SHA-256):

```gleam
pub fn task_hash(t: Task) -> Hash {
  identity.hash_bytes(canonical_bytes(t))
}
```

- Mutations are plain Gleam `fn(Task) -> Task`; the new hash is recomputed.
  Old hash → new hash **is** the history chain.
- Storage: `gleamunison/storage.mnesia(table)` (or `aarondb` if richer queries are wanted).
- Graph: `aarondb/algo/graph` (`cycle_detect` on relation-add; `topological_sort` for `ready`).
- This path involves **no gleamunison eval** — it meets the sub-5 ms NFR trivially.

### Pillar 2 — Mobile rules (the novel path, rare)

When an agent defines a *custom validator, graph predicate, or transition rule that must be
shipped to other agents*, **that** becomes a real Unison `Definition`:

- `codebase.hash_of_definition(def) -> DefinitionRef` — its content address.
- stored in a `Codebase` (`codebase.insert`).
- synced to peers via `gleamunison/sync.pull_sync` / `push_sync`.
- executed on demand via `pipeline.load_and_eval` (or `repl.eval_string`), **not** on every
  task mutation.

Evaluation cost is paid at *registration*, not per-task.

### Composition

Build the actor / graph / storage / sync / CLI layers by **composing aarondb + gleamunison**,
not reimplementing them. `bankai`'s own code is narrow: the `Task` type + canonical serializer +
hash wiring (pillar 1), the rule registry + sync wiring (pillar 2), and the CLI.

## Consequences

**Positive**
- State ops stay sub-5 ms; the perf NFR is met by construction.
- bankai's genuine novelty (pillar 2: content-addressed, mobile, executable rules) is preserved
  without paying for it on every mutation.
- Decoupled pillars mean pillar 1 ships first; pillar 2 adds on without rework.
- Less new code → fewer bugs; graph/actor logic inherits aarondb's existing tests.

**Negative / costs**
- Two persistence/sync substrates: task state (Mnesia + git/JSONL beads-style) and rules
  (gleamunison `Codebase` + `sync`). A later ADR may unify these under one `Codebase`.
- `canonical_bytes(Task)` must be airtight and **versioned** — any change to field order or
  encoding changes every existing hash. It carries a documented version byte.
- Mobile rules require a defined security boundary (executing remotely-provided Unison
  definitions). Out of scope for pillar 1; flagged in the follow-ups below.

**Neutral**
- `beads` (Go/Dolt) remains the *product* reference; `bankai` is its BEAM reimplementation with
  content-addressing substituted for Dolt.

## Alternatives considered

**Option A — Hash data only (drop pillar 2).** Fastest to ship, but `identity.hash_bytes` is
functionally `gleam_crypto` — it discards the entire reason to depend on gleamunison. bankai
becomes "beads on BEAM with SHA-256 IDs." **Rejected:** it abandons the project's premise.

**Option B — Full Unison AST eval per mutation (the spec as written).** Maximally faithful to
"everything is content-addressed executable code," and gleamunison's native `sync` shines. But it
cannot meet the sub-5 ms NFR, carries the highest risk (dynamic BEAM loading under a supervisor),
and is undermined by the project's own cold-start findings. **Rejected** on NFR and risk grounds.

## Verification / follow-up

- **Verify pillar 1** with a unit test: construct a `Task`, `task_hash`, mutate one field, assert
  the hash changes; assert identical inputs produce identical hashes; assert
  `canonical_bytes` is deterministic across runs.
- **Verify the graph** by wiring `aarondb/algo/graph.cycle_detect` into the relation-add path and
  asserting cycles are rejected.
- **Verify sync** (pillar 2, later phase) by `push_sync`-ing a rule `Definition` from one
  `Codebase` and `pull_sync`-ing + `load_and_eval`-ing it in another.
- **Follow-up ADRs:** (1) canonical-serialization versioning; (2) mobile-rule execution
  sandbox / security model; (3) unify state + rule storage under one substrate.

---

## Post-approval amendment (2026-08-03, Phase 0)

**Composition strategy revised: drop the aarondb dependency; keep bankai lean.**

During Phase 0 scaffolding, two facts surfaced that change the "compose aarondb" row of the Composition table:

1. `aarondb/algo/graph.gleam` (which has `cycle_detect`, `topological_sort`, `reachable`) is **coupled to aarondb internals** (`aarondb/fact`, `aarondb/index`, `aarondb/shared/state`). Consuming it requires building an aarondb datom-graph index — not a plain edge list.
2. `aarondb` pulls **lustre / mist / wisp** (web framework) as transitive deps — heavy incidental weight for a CLI that needs none of it.

For a task DAG, cycle-detection and topological sort are ~40 LOC of pure functions over `List(#(String, String))` edges. Rebuilding those is materially simpler than depending on aarondb's index machinery + a web framework.

**Revised composition:**

| bankai concern | Now uses |
|---|---|
| Task-state identity | `gleamunison/identity.hash_bytes` (unchanged) |
| Graph (cycle / topo / ready) | bankai's own small pure `bankai/graph` module |
| Storage | bankai's own `dict` + `simplifile` JSONL |
| Mobile rules (pillar 2) | `gleamunison/codebase` + `sync` + `pipeline` (unchanged — these are gleamunison, not aarondb) |

The **Option 3 decision is unchanged.** Only the "compose aarondb" composition strategy downgrades to "port the trivial math, depend only on gleamunison." This better serves the ADR's own stated intent (avoid incidental complexity; keep bankai's code narrow). `gleamunison v3.9.0` verified to resolve and compile as a path dependency.
