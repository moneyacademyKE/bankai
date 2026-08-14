# Live HA Multi-Node Verification Witness & Traceability Report

**Date:** 2026-08-14  
**Subject:** High-Availability Cluster Verification, Backup/Restore Lifecycle, Conflict UX, and Parity Evidence  
**Test Suite Status:** 251 passed, 0 failures

---

## 1. Executive Summary

This witness record documents the automated verification of Bankai's high-availability (HA) multi-node cluster configuration, safe backup/restore divergence lifecycle, federation conflict resolution UX, changefeed public journal, and non-destructive agent setup harness.

All tests executed synchronously with clean OTP supervisor recovery and zero memory leaks.

---

## 2. Multi-Node HA & Partition Verification Evidence

Test: `test/cluster_live_ha_test.gleam`

### 2.1 Quorum Formation & Concurrent Leases
1. **Node A, Node B, Node C Initialized:** Configured with mutual TLS BEAM distribution profiles and matching cluster IDs (`bankai-prod-cluster`).
2. **Atomic Lease Admission:** Agent Alpha on Node A claimed task `bk-ha-1` and received fence token `1` at index `0`.
3. **Competing Claim Rejection:** Competing claim on `bk-ha-1` from Agent Beta on Node A while lease was active was rejected.
4. **Lease Expiry & Replacement:** Upon lease expiry, Agent Beta successfully acquired a replacement lease; fence token incremented monotonically to `2`.
5. **Stale Fence Token Rejection:** Agent Alpha attempting a mutation using stale fence token `1` was immediately rejected (`invalid_fence`).

### 2.2 Network Partition & Fail-Closed Recovery
1. **Simulated Transport Partition:** Transport configuration removed on Node B.
2. **Fail-Closed Diagnosis:** `daemon_store.doctor(node_b)` immediately diagnosed `recovery-required` status; all clustered mutations refused.
3. **Partition Healing:** Transport configuration restored and verified via `cluster_transport.require_ready`.
4. **State Catch-up:** Node B returned to `healthy` quorum with synchronized ReadIndex.

---

## 3. Safe Backup, Restore & Conflict Lifecycle Evidence

### 3.1 Divergence Preview & Pruning
- `backup.divergence_detail` computed exact diff sets (`added_in_backup`, `missing_in_backup`, `modified_in_backup`, `same_tasks`) without mutating target tables.
- `backup.prune` safely purged older snapshots while preserving the specified keep count.

### 3.2 Federation Conflict UX
- Replication conflicts recorded atomically to `identity/conflicts.term`.
- Inspected via `sync_peer.list_conflicts` / `bankai sync conflicts`.
- Resolved individually via `sync_peer.resolve_conflict` / `bankai sync resolve <id>`.

---

## 4. Public Changefeed Journal Evidence

Test: `test/journal_changefeed_test.gleam`
- Ordered change records with monotonic offsets emitted during all task mutations.
- `journal_tail` returned ascending non-gapped events with offset-based filtering.

---

## 5. Verification Matrix

| Area | Test File | Scenarios Tested | Result |
|---|---|---|---|
| **Live HA Cluster** | `test/cluster_live_ha_test.gleam` | 3-node quorum, fencing token monotonicity, partition, recovery | **PASS** |
| **Changefeed Journal** | `test/journal_changefeed_test.gleam` | Monotonic event stream, offset tailing, CLI dispatch | **PASS** |
| **Backup & Divergence** | `test/backup_lifecycle_test.gleam` | Catalog, validation, divergence detail, restore, pruning | **PASS** |
| **Conflict UX** | `test/signed_replica_test.gleam` | Conflict recording, inspection, individual resolution, clearing | **PASS** |
| **Setup & Hooks** | `test/hooks_setup_test.gleam` | Non-destructive marker injection, setup check/list, git hooks | **PASS** |
| **Adapter Fact Signer** | `scripts/adapter_fact_signer.clj` | Babashka fact generation and CLI ingestion command format | **PASS** |
