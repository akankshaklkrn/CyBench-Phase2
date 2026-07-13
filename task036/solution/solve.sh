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

static olc_node_t *alloc_node(bool is_leaf) {
    olc_node_t *node = (olc_node_t *)calloc(1, sizeof(olc_node_t));
    node->is_leaf = is_leaf;
    node->version_latch = 2; // version 2, unlocked
    return node;
}

static void free_node(olc_node_t *node) {
    if (!node) return;
    if (!node->is_leaf) {
        for (uint32_t i = 0; i <= node->num_keys; i++) {
            free_node(node->children[i]);
        }
    }
    free(node);
}

bool olc_btree_init(olc_btree_t *tree) {
    if (!tree) return false;
    pthread_mutex_init(&tree->root_mutex, NULL);
    tree->root = alloc_node(true);
    return true;
}

void olc_btree_destroy(olc_btree_t *tree) {
    if (!tree) return;
    free_node(tree->root);
    tree->root = NULL;
    pthread_mutex_destroy(&tree->root_mutex);
}

static uint64_t olc_read_lock(olc_node_t *node) {
    uint64_t v;
    do {
        v = __atomic_load_n(&node->version_latch, __ATOMIC_ACQUIRE);
    } while (v & 1);
    return v;
}

static bool olc_validate(olc_node_t *node, uint64_t version) {
    __atomic_thread_fence(__ATOMIC_ACQUIRE);
    uint64_t curr = __atomic_load_n(&node->version_latch, __ATOMIC_RELAXED);
    return curr == version && ((version & 1) == 0);
}

bool olc_btree_lookup(olc_btree_t *tree, uint32_t key, uint32_t *out_val) {
    if (!tree || !tree->root) return false;
    
    int retries = 0;
    while (retries++ < 1000) {
        olc_node_t *curr = __atomic_load_n(&tree->root, __ATOMIC_ACQUIRE);
        uint64_t v = olc_read_lock(curr);
        
        while (!curr->is_leaf) {
            uint32_t idx = 0;
            while (idx < curr->num_keys && key >= curr->keys[idx]) {
                idx++;
            }
            olc_node_t *next = curr->children[idx];
            uint64_t next_v = olc_read_lock(next);
            if (!olc_validate(curr, v)) {
                goto retry;
            }
            curr = next;
            v = next_v;
        }
        
        uint32_t n = curr->num_keys;
        for (uint32_t i = 0; i < n; i++) {
            if (curr->keys[i] == key) {
                uint32_t val = curr->values[i];
                if (olc_validate(curr, v)) {
                    if (out_val) *out_val = val;
                    return true;
                }
                goto retry;
            }
        }
        if (olc_validate(curr, v)) {
            return false;
        }
retry:
        continue;
    }
    return false;
}

static void insert_into_leaf(olc_node_t *leaf, uint32_t key, uint32_t val) {
    uint32_t i = leaf->num_keys;
    while (i > 0 && leaf->keys[i - 1] > key) {
        leaf->keys[i] = leaf->keys[i - 1];
        leaf->values[i] = leaf->values[i - 1];
        i--;
    }
    leaf->keys[i] = key;
    leaf->values[i] = val;
    leaf->num_keys++;
}

static void split_leaf(olc_node_t *leaf, olc_node_t **out_new_leaf, uint32_t *out_split_key) {
    olc_node_t *new_leaf = alloc_node(true);
    uint32_t mid = leaf->num_keys / 2;
    uint32_t move_count = leaf->num_keys - mid;
    
    for (uint32_t i = 0; i < move_count; i++) {
        new_leaf->keys[i] = leaf->keys[mid + i];
        new_leaf->values[i] = leaf->values[mid + i];
    }
    new_leaf->num_keys = move_count;
    leaf->num_keys = mid;
    
    *out_new_leaf = new_leaf;
    *out_split_key = new_leaf->keys[0];
}

static void insert_into_internal(olc_node_t *parent, uint32_t key, olc_node_t *right_child) {
    uint32_t i = parent->num_keys;
    while (i > 0 && parent->keys[i - 1] > key) {
        parent->keys[i] = parent->keys[i - 1];
        parent->children[i + 1] = parent->children[i];
        i--;
    }
    parent->keys[i] = key;
    parent->children[i + 1] = right_child;
    parent->num_keys++;
}

static void split_internal(olc_node_t *node, olc_node_t **out_new_node, uint32_t *out_promoted_key) {
    olc_node_t *new_node = alloc_node(false);
    uint32_t mid = node->num_keys / 2;
    *out_promoted_key = node->keys[mid];
    
    uint32_t move_keys = node->num_keys - mid - 1;
    for (uint32_t i = 0; i < move_keys; i++) {
        new_node->keys[i] = node->keys[mid + 1 + i];
    }
    for (uint32_t i = 0; i <= move_keys; i++) {
        new_node->children[i] = node->children[mid + 1 + i];
    }
    new_node->num_keys = move_keys;
    node->num_keys = mid;
    
    *out_new_node = new_node;
}

static void bump_version(olc_node_t *node) {
    node->version_latch = (node->version_latch + 2);
}

static bool insert_recursive(olc_node_t *node, uint32_t key, uint32_t val,
                             olc_node_t **out_split_node, uint32_t *out_split_key) {
    bump_version(node);
    if (node->is_leaf) {
        for (uint32_t i = 0; i < node->num_keys; i++) {
            if (node->keys[i] == key) {
                node->values[i] = val;
                *out_split_node = NULL;
                return true;
            }
        }
        if (node->num_keys < MAX_KEYS) {
            insert_into_leaf(node, key, val);
            *out_split_node = NULL;
            return true;
        }
        olc_node_t *new_leaf = NULL;
        uint32_t split_key = 0;
        split_leaf(node, &new_leaf, &split_key);
        if (key >= split_key) {
            insert_into_leaf(new_leaf, key, val);
        } else {
            insert_into_leaf(node, key, val);
        }
        *out_split_node = new_leaf;
        *out_split_key = split_key;
        return true;
    } else {
        uint32_t idx = 0;
        while (idx < node->num_keys && key >= node->keys[idx]) {
            idx++;
        }
        olc_node_t *child = node->children[idx];
        olc_node_t *split_child = NULL;
        uint32_t child_split_key = 0;
        insert_recursive(child, key, val, &split_child, &child_split_key);
        
        if (!split_child) {
            *out_split_node = NULL;
            return true;
        }
        if (node->num_keys < MAX_KEYS) {
            insert_into_internal(node, child_split_key, split_child);
            *out_split_node = NULL;
            return true;
        }
        olc_node_t *new_internal = NULL;
        uint32_t prom_key = 0;
        split_internal(node, &new_internal, &prom_key);
        
        if (child_split_key < prom_key) {
            insert_into_internal(node, child_split_key, split_child);
        } else {
            insert_into_internal(new_internal, child_split_key, split_child);
        }
        *out_split_node = new_internal;
        *out_split_key = prom_key;
        return true;
    }
}

bool olc_btree_insert(olc_btree_t *tree, uint32_t key, uint32_t val) {
    if (!tree || !tree->root) return false;
    pthread_mutex_lock(&tree->root_mutex);
    
    olc_node_t *split_node = NULL;
    uint32_t split_key = 0;
    insert_recursive(tree->root, key, val, &split_node, &split_key);
    
    if (split_node) {
        olc_node_t *new_root = alloc_node(false);
        new_root->num_keys = 1;
        new_root->keys[0] = split_key;
        new_root->children[0] = tree->root;
        new_root->children[1] = split_node;
        __atomic_store_n(&tree->root, new_root, __ATOMIC_RELEASE);
    }
    
    pthread_mutex_unlock(&tree->root_mutex);
    return true;
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
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -pthread -fsanitize=address,undefined -o "$OUT_DIR/olc_bench" "$TARGET_PATH"
"$OUT_DIR/olc_bench" > /tmp/out.log
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
