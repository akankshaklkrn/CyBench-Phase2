#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define INF_TIMESTAMP           0xFFFFFFFF
#define MAX_ACTIVE_TXNS         16
#define MAX_KEYS                1024
#define MAX_WRITE_SET           64

#define MVCC_OK                 0
#define MVCC_ERR_NOT_FOUND      (-1)
#define MVCC_ERR_SERIALIZATION_FAILURE (-2)

typedef struct tuple_version {
    uint32_t xmin;
    uint32_t xmax;
    uint32_t key;
    uint32_t value;
    struct tuple_version *prev;
} tuple_version_t;

typedef struct {
    uint32_t snapshot_ts;
    uint32_t active_txns[MAX_ACTIVE_TXNS];
    int num_active;
} snapshot_t;

typedef struct {
    uint32_t txn_id;
    snapshot_t snapshot;
    bool aborted;
    tuple_version_t *write_set[MAX_WRITE_SET];
    int num_writes;
} txn_t;

typedef struct {
    tuple_version_t *index[MAX_KEYS];
} mvcc_db_t;

/* Check if a tuple version is visible to the transaction snapshot */
bool mvcc_is_visible(tuple_version_t *tuple, txn_t *txn) {
    if (!tuple || txn->aborted) return false;

    /* 1. Creation check (xmin) */
    if (tuple->xmin > txn->snapshot.snapshot_ts && tuple->xmin != txn->txn_id) {
        return false;
    }
    if (tuple->xmin != txn->txn_id) {
        for (int i = 0; i < txn->snapshot.num_active; i++) {
            if (tuple->xmin == txn->snapshot.active_txns[i]) {
                return false;
            }
        }
    }

    /* 2. Expiration check (xmax) */
    if (tuple->xmax == INF_TIMESTAMP || tuple->xmax == txn->txn_id) {
        /* If xmax == txn->txn_id, we deleted it right inside our own txn, so NOT visible unless we want prior version? 
           Wait, if tuple->xmax == txn->txn_id, this exact tuple was updated/deleted by US in this transaction. 
           So for reading the current value, this version is no longer visible to US because we created a newer version! */
        if (tuple->xmax == txn->txn_id) return false;
        return true;
    }

    if (tuple->xmax > txn->snapshot.snapshot_ts) {
        return true; // Expired after our snapshot started
    }

    /* If xmax <= snapshot_ts, check if the deleting transaction was active/uncommitted when our snapshot started */
    for (int i = 0; i < txn->snapshot.num_active; i++) {
        if (tuple->xmax == txn->snapshot.active_txns[i]) {
            return true; // Deleting txn was uncommitted, so we still see this version!
        }
    }

    return false;
}

/* Read the visible value for a key under transaction snapshot */
int mvcc_read(mvcc_db_t *db, txn_t *txn, uint32_t key, uint32_t *out_value) {
    if (key >= MAX_KEYS) return MVCC_ERR_NOT_FOUND;
    tuple_version_t *curr = db->index[key];
    while (curr) {
        if (mvcc_is_visible(curr, txn)) {
            *out_value = curr->value;
            return MVCC_OK;
        }
        curr = curr->prev;
    }
    return MVCC_ERR_NOT_FOUND;
}

/* Update or insert a key, creating a new version or returning write-write conflict error */
int mvcc_update(mvcc_db_t *db, txn_t *txn, uint32_t key, uint32_t new_value) {
    if (key >= MAX_KEYS || txn->aborted || txn->num_writes >= MAX_WRITE_SET) {
        return MVCC_ERR_SERIALIZATION_FAILURE;
    }

    tuple_version_t *head = db->index[key];
    if (head != NULL) {
        /* Check write-write conflict: if head xmax is set OR head xmin > our snapshot or in active txns */
        if (head->xmax != INF_TIMESTAMP && head->xmax != txn->txn_id) {
            return MVCC_ERR_SERIALIZATION_FAILURE;
        }
        if (head->xmin > txn->snapshot.snapshot_ts && head->xmin != txn->txn_id) {
            return MVCC_ERR_SERIALIZATION_FAILURE;
        }
        if (head->xmin != txn->txn_id) {
            for (int i = 0; i < txn->snapshot.num_active; i++) {
                if (head->xmin == txn->snapshot.active_txns[i]) {
                    return MVCC_ERR_SERIALIZATION_FAILURE;
                }
            }
        }
        head->xmax = txn->txn_id;
    }

    tuple_version_t *new_tuple = (tuple_version_t *)calloc(1, sizeof(tuple_version_t));
    if (!new_tuple) return MVCC_ERR_SERIALIZATION_FAILURE;

    new_tuple->xmin = txn->txn_id;
    new_tuple->xmax = INF_TIMESTAMP;
    new_tuple->key = key;
    new_tuple->value = new_value;
    new_tuple->prev = head;

    db->index[key] = new_tuple;
    txn->write_set[txn->num_writes++] = new_tuple;

    return MVCC_OK;
}

/* Abort transaction and rollback all versions created in write_set */
void mvcc_abort(mvcc_db_t *db, txn_t *txn) {
    if (txn->aborted) return;
    txn->aborted = true;

    for (int i = 0; i < txn->num_writes; i++) {
        tuple_version_t *v = txn->write_set[i];
        if (!v) continue;
        uint32_t key = v->key;
        if (db->index[key] == v) {
            db->index[key] = v->prev;
        }
        if (v->prev) {
            if (v->prev->xmax == txn->txn_id) {
                v->prev->xmax = INF_TIMESTAMP;
            }
        }
        free(v);
        txn->write_set[i] = NULL;
    }
    txn->num_writes = 0;
}

/* Reclaim memory of obsolete/dead tuple versions across all keys */
int mvcc_vacuum(mvcc_db_t *db, uint32_t oldest_active_ts) {
    int count = 0;
    for (int k = 0; k < MAX_KEYS; k++) {
        tuple_version_t *curr = db->index[k];
        while (curr) {
            tuple_version_t *nxt = curr->prev;
            if (nxt && nxt->xmax != INF_TIMESTAMP && nxt->xmax < oldest_active_ts) {
                /* nxt is obsolete! Unlink nxt and all prior versions or just nxt? 
                   If nxt->xmax < oldest_active_ts, no active or future transaction will ever see nxt!
                   And any version older than nxt (nxt->prev) is also expired even earlier. */
                curr->prev = nxt->prev;
                free(nxt);
                count++;
                continue; // check new curr->prev next
            }
            curr = curr->prev;
        }
    }
    return count;
}

/* Helper to initialize transaction snapshot */
void init_txn(txn_t *txn, uint32_t id, uint32_t ts, uint32_t *active, int num_act) {
    memset(txn, 0, sizeof(*txn));
    txn->txn_id = id;
    txn->snapshot.snapshot_ts = ts;
    txn->snapshot.num_active = num_act;
    for (int i = 0; i < num_act && i < MAX_ACTIVE_TXNS; i++) {
        txn->snapshot.active_txns[i] = active[i];
    }
}

int main(void) {
    int tests_passed = 0;
    uint64_t state_hash = 0x99aabbee11223344ULL;

    mvcc_db_t db;
    memset(&db, 0, sizeof(db));

    uint32_t val = 0;
    int res = 0;

    /* Test 1: Basic Insert & Read */
    txn_t t1;
    init_txn(&t1, 10, 10, NULL, 0);
    res = mvcc_update(&db, &t1, 42, 1000);
    if (res == MVCC_OK && mvcc_read(&db, &t1, 42, &val) == MVCC_OK && val == 1000) {
        tests_passed++;
        state_hash ^= (val * 0x100000001B3ULL);
    } else {
        printf("FAIL: Test 1 basic insert/read failed (res=%d, val=%u)\n", res, val);
    }

    /* Test 2: Snapshot Isolation filtering (T2 starts at ts=15, T1=10 committed. T3 active at ts=15) */
    txn_t t3;
    init_txn(&t3, 12, 12, NULL, 0);
    mvcc_update(&db, &t3, 42, 2000); // T3 creates version 2000 (xmin=12)

    uint32_t active_for_t2[] = {12}; // T3 is active uncommitted when T2 snapshot starts at ts=15
    txn_t t2;
    init_txn(&t2, 15, 15, active_for_t2, 1);
    
    if (mvcc_read(&db, &t2, 42, &val) == MVCC_OK && val == 1000) { // T2 must see 1000 (xmin=10), NOT 2000 (xmin=12 is active)
        tests_passed++;
        state_hash ^= (val * 0x2222333344445555ULL);
    } else {
        printf("FAIL: Test 2 snapshot isolation check failed (val=%u, expected 1000)\n", val);
    }

    /* Test 3: Write-Write Conflict Detection */
    /* T2 attempts to update key 42. But head of key 42 has xmin=12 (T3), which is in T2's active_txns OR > T1's commit */
    res = mvcc_update(&db, &t2, 42, 3000);
    if (res == MVCC_ERR_SERIALIZATION_FAILURE) {
        tests_passed++;
        state_hash ^= 0x777788889999AAAAULL;
    } else {
        printf("FAIL: Test 3 should have returned MVCC_ERR_SERIALIZATION_FAILURE (res=%d)\n", res);
    }

    /* Test 4: Transaction Abort & Rollback */
    mvcc_abort(&db, &t3); // Abort T3, rolling back value 2000 and restoring head to value 1000
    if (db.index[42] != NULL && db.index[42]->value == 1000 && db.index[42]->xmax == INF_TIMESTAMP) {
        tests_passed++;
        state_hash ^= 0xAAAABBBBCCCCDDDDULL;
    } else {
        printf("FAIL: Test 4 abort did not restore prior head value 1000 cleanly\n");
    }

    /* Test 5: Historical Version Chain Traversal */
    txn_t ta, tb, tc;
    init_txn(&ta, 20, 20, NULL, 0);
    mvcc_update(&db, &ta, 100, 10);
    init_txn(&tb, 30, 30, NULL, 0);
    mvcc_update(&db, &tb, 100, 20);
    init_txn(&tc, 40, 40, NULL, 0);
    mvcc_update(&db, &tc, 100, 30);

    /* Snapshot at ts=25 (sees ta's commit at 20, not tb at 30 or tc at 40) */
    txn_t t_read;
    init_txn(&t_read, 25, 25, NULL, 0);
    if (mvcc_read(&db, &t_read, 100, &val) == MVCC_OK && val == 10) {
        tests_passed++;
        state_hash ^= (val * 0xABCDEF0123456789ULL);
    } else {
        printf("FAIL: Test 5 chain traversal wrong historical value %u (expected 10)\n", val);
    }

    /* Test 6: Post-commit visibility */
    init_txn(&t_read, 45, 45, NULL, 0);
    if (mvcc_read(&db, &t_read, 100, &val) == MVCC_OK && val == 30) {
        tests_passed++;
        state_hash ^= (val * 0xFEDCBA9876543210ULL);
    } else {
        printf("FAIL: Test 6 latest visibility check failed (val=%u)\n", val);
    }

    /* Test 7: Vacuuming Obsolete Versions */
    /* Key 100 has chain: [value=30, xmin=40, xmax=INF] -> [value=20, xmin=30, xmax=40] -> [value=10, xmin=20, xmax=30] */
    /* If oldest active transaction in the entire system is at ts=35, any version with xmax < 35 is dead! */
    /* So [value=10, xmin=20, xmax=30] has xmax=30 < 35 -> obsolete. Vacuum must free it and return 1. */
    int reclaimed = mvcc_vacuum(&db, 35);
    if (reclaimed == 1 && db.index[100] != NULL && db.index[100]->prev != NULL && db.index[100]->prev->prev == NULL) {
        tests_passed++;
        state_hash ^= 0x9999999999999999ULL;
    } else {
        printf("FAIL: Test 7 vacuum failed (reclaimed=%d)\n", reclaimed);
    }

    /* Test 8: Multi-key consistency and cleanup */
    txn_t t_multi;
    init_txn(&t_multi, 50, 50, NULL, 0);
    mvcc_update(&db, &t_multi, 1, 111);
    mvcc_update(&db, &t_multi, 2, 222);
    if (mvcc_read(&db, &t_multi, 1, &val) == MVCC_OK && val == 111 &&
        mvcc_read(&db, &t_multi, 2, &val) == MVCC_OK && val == 222) {
        tests_passed++;
        state_hash ^= 0x4242424242424242ULL;
    } else {
        printf("FAIL: Test 8 multi-key check failed\n");
    }

    /* Final Memory Cleanup */
    mvcc_vacuum(&db, INF_TIMESTAMP);
    for (int i = 0; i < MAX_KEYS; i++) {
        tuple_version_t *curr = db.index[i];
        while (curr) {
            tuple_version_t *nxt = curr->prev;
            free(curr);
            curr = nxt;
        }
    }

    if (tests_passed != 8) {
        printf("FAIL: Not all tests passed (%d/8)\n", tests_passed);
        return 1;
    }

    printf("Verification SUCCESS! Dynamic State Hash computed over %d MVCC verification tests.\n", tests_passed);
    printf("cyberbench{mvcc_storage_engine_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
