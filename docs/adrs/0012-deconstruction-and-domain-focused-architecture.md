# ADR-0012: Deconstruction and Domain-Focused Architecture

- **Status**: Accepted
- **Date**: 2026-08-14
- **Context**: 
  Rich Hickey simplicity gap analysis revealed that `daemon_store.gleam` and `cli.gleam` had become monolithic agglomerations of orthogonal concerns (task mutations, queries, relations, diagnostics, backups, interchange). In addition, legacy in-process OTP state actors (`task_actor.gleam`, `store_actor.gleam`) were redundant with Mnesia's strict ACID transaction boundaries.
- **Decision**:
  1. **Decompose `daemon_store` into domain-focused submodules**:
     - `src/bankai/daemon_store/mutations.gleam`: Task creation, update, claim, deferral, labels, priority, and merge.
     - `src/bankai/daemon_store/queries.gleam`: Read-only queries, search, analytics, and projections.
     - `src/bankai/daemon_store/relations.gleam`: Dependency graph, tree traversal, integrity, and cycle validation.
     - `src/bankai/daemon_store/diagnostics.gleam`: Doctor, projection, cluster, and recovery health diagnostics.
     - `src/bankai/daemon_store.gleam`: Clean facade re-exporting and routing to domain submodules.
  2. **Sunset legacy in-process state actors**:
     - Removed `src/bankai/actors/` and `src/bankai/store_actor.gleam`.
     - Direct transactional access via `mnesia_store` and pure mutations via `task_mutation.apply` and `relations.add`.
  3. **Decompose `cli` into focused submodules**:
     - `src/bankai/cli/parser.gleam`: CLI argument parsing and envelopes.
     - `src/bankai/cli/setup.gleam`: Agent setup matrix and marker injection.
     - `src/bankai/cli/maintenance.gleam`: Local legacy maintenance commands.
     - `src/bankai/cli.gleam`: High-cohesion command routing entrypoint.
  4. **Preserve Purity in Workflow and Gate Evaluation**:
     - Templates and adapter facts are pure data structures evaluated without side effects.
- **Consequences**:
  - High cohesion, low coupling, and clear boundaries across all modules.
  - Zero redundant in-process state locks or serialization bottlenecks.
  - Full test suite parity (246 tests passing with 0 failures).
