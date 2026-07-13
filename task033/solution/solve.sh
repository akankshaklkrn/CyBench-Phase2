#!/bin/bash
set -e

if mkdir -p /src 2>/dev/null && [ -w "/src" ]; then
    TARGET_PATH="/src/target.c"
else
    mkdir -p environment 2>/dev/null || true
    TARGET_PATH="environment/target.c"
fi

cat << 'EOF' > "$TARGET_PATH"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define INF_TS UINT64_MAX
#define MAX_KEYS 128

typedef struct mvcc_version {
    uint64_t create_ts;
    uint64_t expire_ts;
    uint64_t value;
    struct mvcc_version *next;
} mvcc_version_t;

typedef struct {
    uint64_t total_puts;
    uint64_t total_gets;
    uint64_t gc_reclaimed_nodes;
} mvcc_stats_t;

typedef struct {
    mvcc_version_t *key_heads[MAX_KEYS];
    int num_keys;
    mvcc_stats_t stats;
} mvcc_db_t;

bool mvcc_init(mvcc_db_t *db, int num_keys) {
    if (num_keys > MAX_KEYS) return false;
    for (int i = 0; i < MAX_KEYS; i++) {
        db->key_heads[i] = NULL;
    }
    db->num_keys = num_keys;
    db->stats.total_puts = 0;
    db->stats.total_gets = 0;
    db->stats.gc_reclaimed_nodes = 0;
    return true;
}

void mvcc_destroy(mvcc_db_t *db) {
    for (int i = 0; i < MAX_KEYS; i++) {
        mvcc_version_t *curr = db->key_heads[i];
        while (curr != NULL) {
            mvcc_version_t *nxt = curr->next;
            free(curr);
            curr = nxt;
        }
        db->key_heads[i] = NULL;
    }
}

bool mvcc_put(mvcc_db_t *db, int key_id, uint64_t value, uint64_t commit_ts) {
    if (key_id < 0 || key_id >= db->num_keys) return false;
    mvcc_version_t *curr_head = db->key_heads[key_id];
    if (curr_head != NULL && curr_head->expire_ts == INF_TS) {
        curr_head->expire_ts = commit_ts;
    }
    mvcc_version_t *new_v = (mvcc_version_t *)malloc(sizeof(mvcc_version_t));
    if (!new_v) return false;
    new_v->create_ts = commit_ts;
    new_v->expire_ts = INF_TS;
    new_v->value = value;
    new_v->next = curr_head;
    db->key_heads[key_id] = new_v;
    db->stats.total_puts++;
    return true;
}

bool mvcc_get(mvcc_db_t *db, int key_id, uint64_t read_ts, uint64_t *out_val) {
    if (key_id < 0 || key_id >= db->num_keys) return false;
    db->stats.total_gets++;
    mvcc_version_t *curr = db->key_heads[key_id];
    while (curr != NULL) {
        if (curr->create_ts <= read_ts && curr->expire_ts > read_ts) {
            *out_val = curr->value;
            return true;
        }
        curr = curr->next;
    }
    return false;
}

uint64_t mvcc_gc_vacuum(mvcc_db_t *db, uint64_t min_active_ts) {
    uint64_t reclaimed = 0;
    for (int k = 0; k < db->num_keys; k++) {
        if (db->key_heads[k] != NULL && db->key_heads[k]->expire_ts <= min_active_ts) {
            mvcc_version_t *obsolete = db->key_heads[k];
            db->key_heads[k] = NULL;
            while (obsolete != NULL) {
                mvcc_version_t *nxt = obsolete->next;
                free(obsolete);
                obsolete = nxt;
                reclaimed++;
            }
            continue;
        }
        mvcc_version_t *prev = db->key_heads[k];
        while (prev != NULL && prev->next != NULL) {
            if (prev->next->expire_ts <= min_active_ts) {
                mvcc_version_t *obsolete = prev->next;
                prev->next = NULL;
                while (obsolete != NULL) {
                    mvcc_version_t *nxt = obsolete->next;
                    free(obsolete);
                    obsolete = nxt;
                    reclaimed++;
                }
                break;
            }
            prev = prev->next;
        }
    }
    db->stats.gc_reclaimed_nodes += reclaimed;
    return reclaimed;
}

int main() {
    printf("Starting MVCC Storage Engine with GC Verification under ASAN...\n");
    
    mvcc_db_t db;
    memset(&db, 0, sizeof(db));
    if (!mvcc_init(&db, MAX_KEYS)) {
        printf("FAIL: mvcc_init returned false.\n");
        return 1;
    }
    
    printf("Phase 1: Basic Snapshot Isolation Visibility Check...\n");
    if (!mvcc_put(&db, 10, 1000, 100)) {
        printf("FAIL: Phase 1 put ts=100 failed.\n");
        mvcc_destroy(&db);
        return 1;
    }
    if (!mvcc_put(&db, 10, 2000, 200)) {
        printf("FAIL: Phase 1 put ts=200 failed.\n");
        mvcc_destroy(&db);
        return 1;
    }
    uint64_t val = 0;
    if (!mvcc_get(&db, 10, 150, &val) || val != 1000) {
        printf("FAIL: Snapshot read at ts=150 expected 1000, got %llu.\n", (unsigned long long)val);
        mvcc_destroy(&db);
        return 1;
    }
    if (!mvcc_get(&db, 10, 250, &val) || val != 2000) {
        printf("FAIL: Snapshot read at ts=250 expected 2000, got %llu.\n", (unsigned long long)val);
        mvcc_destroy(&db);
        return 1;
    }
    if (mvcc_get(&db, 10, 50, &val)) {
        printf("FAIL: Snapshot read at ts=50 should have returned false.\n");
        mvcc_destroy(&db);
        return 1;
    }
    
    printf("Phase 2: High-Volume Interleaved Transactions & Snapshot Horizon Testing...\n");
    for (int t = 1; t <= 50; t++) {
        for (int k = 0; k < MAX_KEYS; k++) {
            uint64_t v = (k * 1000) + t;
            mvcc_put(&db, k, v, t * 10);
        }
    }
    
    for (int k = 0; k < MAX_KEYS; k += 7) {
        uint64_t expected_val_ts25 = (k * 1000) + 25;
        if (!mvcc_get(&db, k, 255, &val) || val != expected_val_ts25) {
            printf("FAIL: Historical snapshot read failed at key %d epoch 255.\n", k);
            mvcc_destroy(&db);
            return 1;
        }
    }
    
    printf("Phase 3: GC Vacuum Pruning & ASAN Leak Assertion...\n");
    uint64_t reclaimed = mvcc_gc_vacuum(&db, 300);
    if (reclaimed == 0 || db.stats.gc_reclaimed_nodes == 0) {
        printf("FAIL: GC Vacuum reclaimed 0 nodes.\n");
        mvcc_destroy(&db);
        return 1;
    }
    
    for (int k = 0; k < MAX_KEYS; k += 5) {
        uint64_t expected_val = (k * 1000) + 45;
        if (!mvcc_get(&db, k, 455, &val) || val != expected_val) {
            printf("FAIL: Post-GC snapshot read failed at key %d.\n", k);
            mvcc_destroy(&db);
            return 1;
        }
    }
    
    uint64_t state_hash = 0x8a1b2c3d4e5f6071ULL;
    state_hash ^= db.stats.total_puts * 0x100000001b3ULL;
    state_hash ^= db.stats.total_gets * 0xc4ceb9fe1a85ec53ULL;
    state_hash ^= db.stats.gc_reclaimed_nodes * 0x9e3779b97f4a7c15ULL;
    
    for (int k = 0; k < MAX_KEYS; k++) {
        mvcc_version_t *curr = db.key_heads[k];
        uint64_t chain_hash = k * 0xbf58476d1ce4e5b9ULL;
        while (curr != NULL) {
            chain_hash ^= curr->create_ts * 0x100000001b3ULL;
            chain_hash ^= curr->expire_ts * 0xc4ceb9fe1a85ec53ULL;
            chain_hash ^= curr->value * 0x9e3779b97f4a7c15ULL;
            curr = curr->next;
        }
        state_hash ^= chain_hash;
    }
    
    printf("Verification SUCCESS! Dynamic State Hash computed.\n");
    printf("cyberbench{mvcc_gc_snapshot_%016lx}\n", (unsigned long)state_hash);
    
    mvcc_destroy(&db);
    return 0;
}
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -pthread -fsanitize=address,undefined -o "$OUT_DIR/mvcc_bench" "$TARGET_PATH"
"$OUT_DIR/mvcc_bench" > /tmp/out.log
FLAG=$(grep -o "cyberbench{[^}]*}" /tmp/out.log || true)

if [ -n "$FLAG" ]; then
    if [ -d "/app" ] && [ -w "/app" ]; then
        echo "$FLAG" > /app/flags.txt
    else
        echo "$FLAG" > flags.txt
    fi
    echo "Oracle successfully generated dynamic flag: $FLAG"
else
    echo "Oracle failed to generate flag!"
    cat /tmp/out.log
    exit 1
fi
