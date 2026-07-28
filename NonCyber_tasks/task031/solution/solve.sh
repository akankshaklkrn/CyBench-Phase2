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
#include <pthread.h>
#include <assert.h>
#include <unistd.h>

#define NUM_STRIPES 32
#define MAX_KICKS 100
#define TABLE_CAPACITY 8192

typedef struct {
    uint64_t key;
    uint64_t val;
    bool is_occupied;
} cuckoo_entry_t;

typedef struct {
    cuckoo_entry_t *table_a;
    cuckoo_entry_t *table_b;
    pthread_mutex_t stripes[NUM_STRIPES];
    size_t capacity;
} cuckoo_table_t;

static inline uint64_t hash_a(uint64_t k) {
    k ^= k >> 33;
    k *= 0xff51afd7ed558ccdULL;
    k ^= k >> 33;
    k *= 0xc4ceb9fe1a85ec53ULL;
    k ^= k >> 33;
    return k;
}

static inline uint64_t hash_b(uint64_t k) {
    uint64_t hash = 0xcbf29ce484222325ULL;
    for (int i = 0; i < 8; i++) {
        hash ^= (k >> (i * 8)) & 0xff;
        hash *= 0x100000001b3ULL;
    }
    return hash;
}

static inline uint64_t entry_hash(uint64_t k, uint64_t v) {
    uint64_t h = k ^ (v * 0x100000001b3ULL);
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return h;
}

static inline void lock_two_stripes(cuckoo_table_t *table, int s1, int s2) {
    if (s1 == s2) {
        pthread_mutex_lock(&table->stripes[s1]);
    } else if (s1 < s2) {
        pthread_mutex_lock(&table->stripes[s1]);
        pthread_mutex_lock(&table->stripes[s2]);
    } else {
        pthread_mutex_lock(&table->stripes[s2]);
        pthread_mutex_lock(&table->stripes[s1]);
    }
}

static inline void unlock_two_stripes(cuckoo_table_t *table, int s1, int s2) {
    if (s1 == s2) {
        pthread_mutex_unlock(&table->stripes[s1]);
    } else {
        pthread_mutex_unlock(&table->stripes[s1]);
        pthread_mutex_unlock(&table->stripes[s2]);
    }
}

static inline void lock_all_stripes(cuckoo_table_t *table) {
    for (int i = 0; i < NUM_STRIPES; i++) {
        pthread_mutex_lock(&table->stripes[i]);
    }
}

static inline void unlock_all_stripes(cuckoo_table_t *table) {
    for (int i = NUM_STRIPES - 1; i >= 0; i--) {
        pthread_mutex_unlock(&table->stripes[i]);
    }
}

bool cuckoo_init(cuckoo_table_t *table, size_t cap) {
    table->table_a = (cuckoo_entry_t *)calloc(cap, sizeof(cuckoo_entry_t));
    table->table_b = (cuckoo_entry_t *)calloc(cap, sizeof(cuckoo_entry_t));
    if (!table->table_a || !table->table_b) return false;
    for (int i = 0; i < NUM_STRIPES; i++) {
        pthread_mutex_init(&table->stripes[i], NULL);
    }
    table->capacity = cap;
    return true;
}

void cuckoo_destroy(cuckoo_table_t *table) {
    for (int i = 0; i < NUM_STRIPES; i++) {
        pthread_mutex_destroy(&table->stripes[i]);
    }
    free(table->table_a);
    free(table->table_b);
}

bool cuckoo_lookup(cuckoo_table_t *table, uint64_t key, uint64_t *val_out) {
    size_t idx_a = hash_a(key) % table->capacity;
    size_t idx_b = hash_b(key) % table->capacity;
    int s1 = idx_a % NUM_STRIPES;
    int s2 = idx_b % NUM_STRIPES;
    
    lock_two_stripes(table, s1, s2);
    if (table->table_a[idx_a].is_occupied && table->table_a[idx_a].key == key) {
        if (val_out) *val_out = table->table_a[idx_a].val;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    if (table->table_b[idx_b].is_occupied && table->table_b[idx_b].key == key) {
        if (val_out) *val_out = table->table_b[idx_b].val;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    unlock_two_stripes(table, s1, s2);
    return false;
}

bool cuckoo_delete(cuckoo_table_t *table, uint64_t key) {
    size_t idx_a = hash_a(key) % table->capacity;
    size_t idx_b = hash_b(key) % table->capacity;
    int s1 = idx_a % NUM_STRIPES;
    int s2 = idx_b % NUM_STRIPES;
    
    lock_two_stripes(table, s1, s2);
    if (table->table_a[idx_a].is_occupied && table->table_a[idx_a].key == key) {
        table->table_a[idx_a].is_occupied = false;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    if (table->table_b[idx_b].is_occupied && table->table_b[idx_b].key == key) {
        table->table_b[idx_b].is_occupied = false;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    unlock_two_stripes(table, s1, s2);
    return false;
}

bool cuckoo_insert(cuckoo_table_t *table, uint64_t key, uint64_t val) {
    size_t idx_a = hash_a(key) % table->capacity;
    size_t idx_b = hash_b(key) % table->capacity;
    int s1 = idx_a % NUM_STRIPES;
    int s2 = idx_b % NUM_STRIPES;
    
    lock_two_stripes(table, s1, s2);
    if (table->table_a[idx_a].is_occupied && table->table_a[idx_a].key == key) {
        table->table_a[idx_a].val = val;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    if (table->table_b[idx_b].is_occupied && table->table_b[idx_b].key == key) {
        table->table_b[idx_b].val = val;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    if (!table->table_a[idx_a].is_occupied) {
        table->table_a[idx_a].key = key;
        table->table_a[idx_a].val = val;
        table->table_a[idx_a].is_occupied = true;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    if (!table->table_b[idx_b].is_occupied) {
        table->table_b[idx_b].key = key;
        table->table_b[idx_b].val = val;
        table->table_b[idx_b].is_occupied = true;
        unlock_two_stripes(table, s1, s2);
        return true;
    }
    unlock_two_stripes(table, s1, s2);
    
    lock_all_stripes(table);
    if (!table->table_a[idx_a].is_occupied) {
        table->table_a[idx_a].key = key;
        table->table_a[idx_a].val = val;
        table->table_a[idx_a].is_occupied = true;
        unlock_all_stripes(table);
        return true;
    }
    if (!table->table_b[idx_b].is_occupied) {
        table->table_b[idx_b].key = key;
        table->table_b[idx_b].val = val;
        table->table_b[idx_b].is_occupied = true;
        unlock_all_stripes(table);
        return true;
    }
    
    uint64_t cur_key = key;
    uint64_t cur_val = val;
    bool in_table_a = true;
    size_t cur_idx = idx_a;
    
    for (int kick = 0; kick < MAX_KICKS; kick++) {
        if (in_table_a) {
            uint64_t evicted_k = table->table_a[cur_idx].key;
            uint64_t evicted_v = table->table_a[cur_idx].val;
            table->table_a[cur_idx].key = cur_key;
            table->table_a[cur_idx].val = cur_val;
            table->table_a[cur_idx].is_occupied = true;
            cur_key = evicted_k;
            cur_val = evicted_v;
            cur_idx = hash_b(cur_key) % table->capacity;
            if (!table->table_b[cur_idx].is_occupied) {
                table->table_b[cur_idx].key = cur_key;
                table->table_b[cur_idx].val = cur_val;
                table->table_b[cur_idx].is_occupied = true;
                unlock_all_stripes(table);
                return true;
            }
            in_table_a = false;
        } else {
            uint64_t evicted_k = table->table_b[cur_idx].key;
            uint64_t evicted_v = table->table_b[cur_idx].val;
            table->table_b[cur_idx].key = cur_key;
            table->table_b[cur_idx].val = cur_val;
            table->table_b[cur_idx].is_occupied = true;
            cur_key = evicted_k;
            cur_val = evicted_v;
            cur_idx = hash_a(cur_key) % table->capacity;
            if (!table->table_a[cur_idx].is_occupied) {
                table->table_a[cur_idx].key = cur_key;
                table->table_a[cur_idx].val = cur_val;
                table->table_a[cur_idx].is_occupied = true;
                unlock_all_stripes(table);
                return true;
            }
            in_table_a = true;
        }
    }
    unlock_all_stripes(table);
    return false;
}

typedef struct {
    cuckoo_table_t *table;
    int thread_id;
    int num_ops;
} worker_arg_t;

void *worker_phase2(void *arg) {
    worker_arg_t *w = (worker_arg_t *)arg;
    for (int i = 0; i < w->num_ops; i++) {
        uint64_t key = (w->thread_id * 10000) + i + 1;
        if (!cuckoo_insert(w->table, key, key * 10)) {
            return (void *)(intptr_t)0;
        }
    }
    return (void *)(intptr_t)1;
}

void *worker_phase3(void *arg) {
    worker_arg_t *w = (worker_arg_t *)arg;
    for (int i = 0; i < w->num_ops; i++) {
        uint64_t key = (w->thread_id * 10000) + i + 1;
        uint64_t val = 0;
        if (!cuckoo_lookup(w->table, key, &val) || val != key * 10) {
            return (void *)(intptr_t)0;
        }
    }
    return (void *)(intptr_t)1;
}

void *worker_phase4(void *arg) {
    worker_arg_t *w = (worker_arg_t *)arg;
    for (int i = 0; i < w->num_ops; i += 2) {
        uint64_t key = (w->thread_id * 10000) + i + 1;
        if (!cuckoo_delete(w->table, key)) {
            return (void *)(intptr_t)0;
        }
    }
    return (void *)(intptr_t)1;
}

int main() {
    printf("Starting Concurrent Striped Cuckoo Hash Table Verification under TSAN...\n");
    
    cuckoo_table_t table;
    if (!cuckoo_init(&table, TABLE_CAPACITY)) {
        printf("FAIL: cuckoo_init returned false.\n");
        return 1;
    }
    
    printf("Executing Phase 1: Baseline insertion and kicks...\n");
    for (uint64_t i = 100; i < 500; i++) {
        if (!cuckoo_insert(&table, i, i * 3)) {
            printf("FAIL: Phase 1 insertion failed at key %lu.\n", (unsigned long)i);
            cuckoo_destroy(&table);
            return 1;
        }
    }
    for (uint64_t i = 100; i < 500; i++) {
        uint64_t val = 0;
        if (!cuckoo_lookup(&table, i, &val) || val != i * 3) {
            printf("FAIL: Phase 1 lookup failed at key %lu.\n", (unsigned long)i);
            cuckoo_destroy(&table);
            return 1;
        }
    }
    
    printf("Executing Phase 2: Concurrent Striped Insertions (8 threads)...\n");
    pthread_t threads[8];
    worker_arg_t args[8];
    for (int t = 0; t < 8; t++) {
        args[t].table = &table;
        args[t].thread_id = t + 1;
        args[t].num_ops = 500;
        pthread_create(&threads[t], NULL, worker_phase2, &args[t]);
    }
    for (int t = 0; t < 8; t++) {
        void *ret;
        pthread_join(threads[t], &ret);
        if ((intptr_t)ret == 0) {
            printf("FAIL: Phase 2 concurrent insertion failed in thread %d.\n", t + 1);
            cuckoo_destroy(&table);
            return 1;
        }
    }
    
    printf("Executing Phase 3: Concurrent Lookups (8 threads)...\n");
    for (int t = 0; t < 8; t++) {
        pthread_create(&threads[t], NULL, worker_phase3, &args[t]);
    }
    for (int t = 0; t < 8; t++) {
        void *ret;
        pthread_join(threads[t], &ret);
        if ((intptr_t)ret == 0) {
            printf("FAIL: Phase 3 concurrent lookup failed in thread %d.\n", t + 1);
            cuckoo_destroy(&table);
            return 1;
        }
    }
    
    printf("Executing Phase 4: Concurrent Deletions (8 threads)...\n");
    for (int t = 0; t < 8; t++) {
        pthread_create(&threads[t], NULL, worker_phase4, &args[t]);
    }
    for (int t = 0; t < 8; t++) {
        void *ret;
        pthread_join(threads[t], &ret);
        if ((intptr_t)ret == 0) {
            printf("FAIL: Phase 4 concurrent deletion failed in thread %d.\n", t + 1);
            cuckoo_destroy(&table);
            return 1;
        }
    }
    
    uint64_t state_hash = 0xcbf29ce484222325ULL;
    for (size_t i = 0; i < table.capacity; i++) {
        if (table.table_a[i].is_occupied) {
            state_hash ^= entry_hash(table.table_a[i].key, table.table_a[i].val);
        }
        if (table.table_b[i].is_occupied) {
            state_hash ^= entry_hash(table.table_b[i].key, table.table_b[i].val);
        }
    }
    
    printf("Verification SUCCESS! Dynamic State Hash computed.\n");
    printf("cyberbench{cuckoo_tsan_striped_%016lx}\n", (unsigned long)state_hash);
    
    cuckoo_destroy(&table);
    return 0;
}
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -pthread -fsanitize=address,undefined -o "$OUT_DIR/cuckoo_bench" "$TARGET_PATH"
"$OUT_DIR/cuckoo_bench" > /tmp/out.log
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
