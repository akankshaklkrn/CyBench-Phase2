#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <pthread.h>
#include <assert.h>

#define MAX_KEYS 15
#define MAX_CHILDREN 16
#define NUM_THREADS 8
#define KEYS_PER_THREAD 500

typedef struct olc_node {
    uint64_t version_latch;
    bool is_leaf;
    uint32_t num_keys;
    uint32_t keys[MAX_KEYS];
    union {
        uint32_t values[MAX_KEYS];
        struct olc_node *children[MAX_CHILDREN];
    };
} olc_node_t;

typedef struct {
    olc_node_t *root;
    pthread_mutex_t root_mutex;
} olc_btree_t;

bool olc_btree_init(olc_btree_t *tree) {
    return false;
}

void olc_btree_destroy(olc_btree_t *tree) {
}

bool olc_btree_lookup(olc_btree_t *tree, uint32_t key, uint32_t *out_val) {
    return false;
}

bool olc_btree_insert(olc_btree_t *tree, uint32_t key, uint32_t val) {
    return false;
}

typedef struct {
    olc_btree_t *tree;
    int thread_id;
} thread_arg_t;

void *worker_thread(void *arg) {
    thread_arg_t *targ = (thread_arg_t *)arg;
    int tid = targ->thread_id;
    for (int i = 0; i < KEYS_PER_THREAD; i++) {
        uint32_t key = (tid * KEYS_PER_THREAD) + i + 1;
        uint32_t expected = key * 13 + 7;
        uint32_t val = 0;
        bool ok = olc_btree_lookup(targ->tree, key, &val);
        if (!ok || val != expected) {
            fprintf(stderr, "FAIL: Thread %d lookup error on key %u (got %u)\n", tid, key, val);
            return (void *)1;
        }
    }
    return NULL;
}

static void traverse_hash(olc_node_t *node, uint64_t *state_hash, uint64_t *leaf_count) {
    if (!node) return;
    if (node->is_leaf) {
        (*leaf_count)++;
        for (uint32_t i = 0; i < node->num_keys; i++) {
            uint64_t h = node->keys[i] * 0x9e3779b97f4a7c15ULL;
            h ^= node->values[i] * 0xbf58476d1ce4e5b9ULL;
            *state_hash ^= h;
        }
    } else {
        for (uint32_t i = 0; i <= node->num_keys; i++) {
            traverse_hash(node->children[i], state_hash, leaf_count);
        }
    }
}

int main() {
    printf("Starting Optimistic Lock Coupling (OLC) B-Tree Verification under ASAN...\n");
    
    olc_btree_t tree;
    if (!olc_btree_init(&tree)) {
        printf("FAIL: olc_btree_init returned false.\n");
        return 1;
    }
    
    printf("Executing Phase 1: Deterministic B-Tree Construction (4,000 keys)...\n");
    for (uint32_t k = 1; k <= NUM_THREADS * KEYS_PER_THREAD; k++) {
        uint32_t val = k * 13 + 7;
        if (!olc_btree_insert(&tree, k, val)) {
            printf("FAIL: Phase 1 insert failed at key %u\n", k);
            olc_btree_destroy(&tree);
            return 1;
        }
    }
    
    printf("Executing Phase 2: Multi-Threaded Optimistic Concurrent Lookups (%d threads)...\n", NUM_THREADS);
    pthread_t threads[NUM_THREADS];
    thread_arg_t args[NUM_THREADS];
    for (int i = 0; i < NUM_THREADS; i++) {
        args[i].tree = &tree;
        args[i].thread_id = i;
        pthread_create(&threads[i], NULL, worker_thread, &args[i]);
    }
    
    for (int i = 0; i < NUM_THREADS; i++) {
        void *res = NULL;
        pthread_join(threads[i], &res);
        if (res != NULL) {
            printf("FAIL: Thread %d reported optimistic lookup error.\n", i);
            olc_btree_destroy(&tree);
            return 1;
        }
    }
    
    uint64_t state_hash = 0x8a7b6c5d4e3f2a10ULL;
    uint64_t leaf_count = 0;
    traverse_hash(tree.root, &state_hash, &leaf_count);
    state_hash ^= leaf_count * 0xc4ceb9fe1a85ec53ULL;
    
    printf("Verification SUCCESS! Dynamic State Hash computed across %llu leaves.\n", (unsigned long long)leaf_count);
    printf("cyberbench{olc_btree_state_%016lx}\n", (unsigned long)state_hash);
    
    olc_btree_destroy(&tree);
    return 0;
}
