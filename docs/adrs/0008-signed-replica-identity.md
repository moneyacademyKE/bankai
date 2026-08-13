# ADR-0008: Signed Replica Identity and Causal Snapshot Transport

**Status:** Accepted
**Date:** 2026-08-12
**Extends:** ADR-0007

## Decision

Bankai peer replication uses a `bankai-replica-v2` AaronDB `envelope` around a
versioned `bankai-replica-payload-v1` snapshot. The envelope has an Ed25519
signature, Bankai-specific domain separator, payload hash, signer key epoch,
logical clock, and causal-parent list.

Each workspace owns a local Ed25519 seed beneath `.bankai/identity/`. It is
not exported, stored in task Mnesia tables, or admitted through task JSONL.
Trust is explicit: the receiving workspace must add a peer public key before
accepting a frame. Revocation makes subsequent frames fail before decode or
Mnesia import. A signature is considered replayed after its successful
application and is rejected before a second import.

## Authority and conflict rules

- Mnesia remains the sole task-state authority.
- An envelope only authenticates a snapshot candidate; it does not decide a
  Bankai head merge.
- Bankai validates canonical task hashes and head divergence after envelope
  verification. Divergent heads are rejected by the transactional repository
  and recorded as a replica conflict artifact.
- Legacy JSONL remains a local, unsigned migration/import format. It is not
  accepted on the network transport.

## Consequences

The peer protocol has a deliberate provisioning step: copy a peer public key
into the local trust store before first exchange. This is a feature, not setup
friction disguised as a bug; accepting the first network signer is TOFU and
would undermine the rig boundary.

This provides signed causal replication, not consensus. Clustered commands and
fenced claims remain a separate authority mode under ADR-0007.
