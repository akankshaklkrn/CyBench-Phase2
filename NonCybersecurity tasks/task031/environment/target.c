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

bool cuckoo_init(cuckoo_table_t *table, size_t cap) {
    return false;
}

void cuckoo_destroy(cuckoo_table_t *table) {
}

bool cuckoo_lookup(cuckoo_table_t *table, uint64_t key, uint64_t *val_out) {
    return false;
}

bool cuckoo_insert(cuckoo_table_t *table, uint64_t key, uint64_t val) {
    return false;
}

bool cuckoo_delete(cuckoo_table_t *table, uint64_t key) {
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
