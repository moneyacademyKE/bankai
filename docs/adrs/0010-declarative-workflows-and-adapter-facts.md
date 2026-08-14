# ADR-0010: Declarative workflow templates and optional adapter facts

**Status:** Accepted

**Date:** 2026-08-13

**Tracking:** [#6](https://github.com/moneyacademyKE/bankai/issues/6)

## Context

Useful Beads parity requires reusable workflow graphs and external gate/provider integration. Two tempting shortcuts would damage Bankai's architecture:

1. treat Gleamunison executable rules as workflow templates; or
2. let provider clients call networks and mutate readiness/task truth directly.

The first hides workflow state behind code. The second makes credentials, network availability, provider semantics, and task readiness one complected operation. Both would create competing authorities alongside daemon-owned Mnesia.

## Decision

### Molecules are immutable declarative data

Bankai will model reusable workflows as versioned, content-addressed DAG templates stored in dedicated Mnesia tables. A template declares nodes, typed edges, variables, defaults, and schema version. It contains no executable code.

Instantiation validates the complete template and bindings before one Mnesia transaction creates all tasks, relations, instance provenance, and an idempotency record. The identity tuple `(template_hash, idempotency_key)` owns retry behavior: an identical retry returns the same instance; different bindings under the same key fail.

Gleamunison rules may validate a bounded immutable representation or derive an annotation. They cannot create hidden workflow state or write tasks.

### External systems produce authenticated facts through adapters

GitHub, CI, trackers, and embedding providers remain optional out-of-core adapters. A gate adapter can submit a signed, issuer-scoped, expiry-bearing fact. Bankai validates and stores the fact; pure local gate policy decides readiness from stored data. Readiness never performs a hidden network call.

Embedding adapters may enrich derived retrieval. The deterministic lexical implementation remains available and task truth never depends on an embedding provider.

### Public journal is conditional

Bankai's ordered committed-change log may expose a bounded journal projection with explicit checkpoints, retention floor, truncation errors, and tail limits when a concrete consumer requires it. HTTP/SSE is not part of this decision and will not be added merely to resemble another product.

## Consequences

### Positive

- Workflow structure remains inspectable data.
- Template instantiation can be validated, atomic, idempotent, and auditable.
- Mobile rules retain a narrow pure-policy role.
- Provider outages and credentials cannot silently redefine readiness.
- Optional integrations compose at the boundary instead of inflating the core.

### Costs

- Templates need dedicated versioned storage, validation, provenance, and protocol operations.
- Adapters must sign and refresh facts explicitly.
- Some Beads integrations will remain out of process and require operator configuration.

## Rejected alternatives

- **Executable templates:** rejected because code hides graph shape and mutation intent.
- **Provider-specific fields on `Task`:** rejected because it pollutes the task model and couples core history to vendor schemas.
- **Live network checks inside readiness:** rejected because deterministic local policy must remain credential-free and available offline.
- **Dolt/SQL template authority:** rejected because Mnesia already owns Bankai domain truth.
- **Always-on HTTP/SSE journal:** deferred until a measured consumer exists.

## Verification

- Template validation writes nothing on malformed variables, endpoints, parents, or cycles.
- Instantiation is one transaction and identical retries return one instance.
- Provenance is queryable from template to instance/task and back.
- Expired, unsigned, wrong-issuer, and replayed adapter facts are rejected.
- Readiness produces identical results without network access.
- Lexical retrieval remains functional with every adapter disabled.
