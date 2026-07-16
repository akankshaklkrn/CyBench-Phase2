# CyBench Ultra-Challenge: Multi-Version Concurrency Control (MVCC) & Snapshot Isolation Engine

You are tasked with implementing a user-space **Multi-Version Concurrency Control (MVCC) Storage Engine** in C inside `/src/target.c`.

## Background & Motivation

Modern relational and key-value database engines (such as PostgreSQL, MySQL InnoDB, and CockroachDB) use **Multi-Version Concurrency Control (MVCC)** to provide non-blocking reads and strict transaction isolation (`Snapshot Isolation` and `Serializable Snapshot Isolation`). Instead of overwriting existing records in place, updates and deletes create new version tuples or expire old tuples by setting version timestamps (`xmin` and `xmax`). A transaction reads only the versions visible to its specific snapshot, ensuring read-only transactions never block writers and writers never block readers.

## Architecture & Specification

The skeleton codebase in `/src/target.c` defines:
1. **Version Chain & Transaction Data Structures**:
   - `INF_TIMESTAMP` (`0xFFFFFFFF`): Indicates a tuple version is active (not deleted or superseded).
   - `tuple_version_t`:
     - `uint32_t xmin`: Creation timestamp / transaction ID (`txn_id`) that created this version.
     - `uint32_t xmax`: Deletion/expiration timestamp / transaction ID (`txn_id`) that superseded or deleted this version (defaults to `INF_TIMESTAMP`).
     - `uint32_t key`: Record key identifier.
     - `uint32_t value`: Data payload.
     - `tuple_version_t *prev`: Pointer to the older historical version in the chain (or `NULL` if oldest).
   - `snapshot_t`:
     - `uint32_t snapshot_ts`: Start timestamp of the transaction.
     - `uint32_t active_txns[MAX_ACTIVE_TXNS]`: Array of transaction IDs that were active (uncommitted) when this snapshot was taken.
     - `int num_active`: Number of active uncommitted transactions.
   - `txn_t`:
     - `uint32_t txn_id`: Unique transaction identifier (`> 0`).
     - `snapshot_t snapshot`: The transaction's read snapshot.
     - `bool aborted`: Set if the transaction was aborted.

2. **Core MVCC Functions to Implement**:
   - `bool mvcc_is_visible(tuple_version_t *tuple, txn_t *txn)`:
     - Determines whether a specific version tuple is visible to transaction `txn`.
     - Visibility Rules:
       1. **Creation check (`xmin`)**: The version must have been created before or at the snapshot start (`tuple->xmin <= txn->snapshot.snapshot_ts`) AND `tuple->xmin` must **NOT** be in `txn->snapshot.active_txns[]` (unless `tuple->xmin == txn->txn_id`, i.e., created by the transaction itself).
       2. **Expiration check (`xmax`)**: The version must not be expired relative to this snapshot. That means either:
          - `tuple->xmax == INF_TIMESTAMP`, OR
          - `tuple->xmax > txn->snapshot.snapshot_ts`, OR
          - `tuple->xmax` **IS** in `txn->snapshot.active_txns[]` and `tuple->xmax != txn->txn_id` (meaning the deleting transaction was uncommitted when our snapshot started).
     - Return `true` if visible under both rules, `false` otherwise.

   - `int mvcc_read(mvcc_db_t *db, txn_t *txn, uint32_t key, uint32_t *out_value)`:
     - Traverses the version chain for `key` starting from the head (`db->index[key]`).
     - Finds the first (most recent) `tuple_version_t` along the chain where `mvcc_is_visible(version, txn)` returns `true`.
     - If visible version found, copies `value` to `*out_value` and returns `MVCC_OK` (`0`).
     - If no visible version exists for `key`, returns `MVCC_ERR_NOT_FOUND` (`-1`).

   - `int mvcc_update(mvcc_db_t *db, txn_t *txn, uint32_t key, uint32_t new_value)`:
     - Traverses the version chain for `key` (`db->index[key]`).
     - **Write-Write Conflict / Serialization Check**:
       - If the head (latest) version of `key` exists and has `tuple->xmax != INF_TIMESTAMP` (already updated/deleted by another transaction that is committed or active) OR `tuple->xmin > txn->snapshot.snapshot_ts` (created by a concurrent transaction after our snapshot), return `MVCC_ERR_SERIALIZATION_FAILURE` (`-2`).
     - If no conflict occurs:
       - Set the head version's `xmax = txn->txn_id` (if head exists).
       - Allocate a new `tuple_version_t` with `xmin = txn->txn_id`, `xmax = INF_TIMESTAMP`, `key = key`, `value = new_value`, and link `prev = old_head`.
       - Update `db->index[key]` to point to this newly created version.
       - Track this modification in `txn->write_set` so it can be rolled back if aborted.
       - Return `MVCC_OK` (`0`).

   - `void mvcc_abort(mvcc_db_t *db, txn_t *txn)`:
     - Rolls back all modifications made by `txn` recorded in `txn->write_set`.
     - For each version `V` created by `txn`: if `V == db->index[V->key]`, restore `db->index[V->key] = V->prev`. If `V->prev` is not `NULL`, reset `V->prev->xmax = INF_TIMESTAMP`. Free memory allocated for `V`.
     - Mark `txn->aborted = true`.

   - `int mvcc_vacuum(mvcc_db_t *db, uint32_t oldest_active_ts)`:
     - Reclaims physical memory of dead version tuples across all keys.
     - A historical version `V` (where `V != db->index[V->key]`) is **dead/obsolete** if `V->xmax != INF_TIMESTAMP` and `V->xmax < oldest_active_ts`.
     - Unlink and `free()` all dead versions without disrupting active version chains.
     - Return the count of vacuumed tuples.

## Verification & Objectives

The test harness in `main()` runs 8 rigorous verification scenarios:
1. **Test 1**: Basic insert, version chain creation, and `mvcc_read` visibility check.
2. **Test 2**: Snapshot Isolation verification between concurrent active transactions (`active_txns` filtering).
3. **Test 3**: Write-Write conflict trapping (`MVCC_ERR_SERIALIZATION_FAILURE`) on concurrent key modification.
4. **Test 4**: Transaction Abort & Rollback (`mvcc_abort`), confirming exact restoration of prior visible state.
5. **Test 5**: Deep historical version traversal across a 5-update chain.
6. **Test 6**: Post-commit visibility updates across sequential snapshots.
7. **Test 7**: Vacuuming (`mvcc_vacuum`) verifying exact physical memory cleanup of obsolete tuples under AddressSanitizer without freeing active versions.
8. **Test 8**: Multi-key transactional atomicity and state consistency.

## Instructions

1. Complete the implementation inside `/src/target.c`.
2. Compile your implementation using:
   ```bash
   gcc -O2 -Wall -Werror -fsanitize=address,undefined -o /out/mvcc_bench /src/target.c
   ```
3. Run `/out/mvcc_bench` to verify all 8 tests pass and obtain the verification flag:
   ```
   cyberbench{mvcc_storage_engine_state_<hash>}
   ```
4. Save the output flag to `/app/flags.txt` or `/logs/agent/flags.txt`.
