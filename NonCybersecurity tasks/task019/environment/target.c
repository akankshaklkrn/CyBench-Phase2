#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>

#define MAX_LEVEL 8
#define NUM_THREADS 16

typedef struct skiplist_node {
    int key;
    int top_level;
    _Atomic(struct skiplist_node *) next[MAX_LEVEL];
} skiplist_node;

typedef struct skiplist_t {
    skiplist_node *header;
} skiplist_t;

skiplist_t sl;
_Atomic int total_inserted = 0;

// TODO: Implement lock-free insert and search
bool skiplist_insert(skiplist_t *sl, int key, int top_level) {
    // Implement atomic multi-level CAS splicing
    return false;
}

bool skiplist_search(skiplist_t *sl, int key) {
    // Implement lock-free multi-level traversal
    return false;
}

void init_skiplist(skiplist_t *sl) {
    sl->header = malloc(sizeof(skiplist_node));
    sl->header->key = -1;
    sl->header->top_level = MAX_LEVEL - 1;
    for (int i = 0; i < MAX_LEVEL; i++) {
        atomic_init(&sl->header->next[i], NULL);
    }
}

void* thread_func(void* arg) {
    int thread_id = *(int*)arg;
    int start_key = thread_id * 5000;
    for (int i = 0; i < 5000; i++) {
        int key = start_key + i;
        int lvl = 0;
        // Simple deterministic level generation for test consistency
        int h = key;
        while ((h & 1) && lvl < MAX_LEVEL - 1) {
            lvl++;
            h >>= 1;
        }
        if (skiplist_insert(&sl, key, lvl)) {
            atomic_fetch_add(&total_inserted, 1);
        }
    }
    
    // Verify all keys inserted by this thread can be found
    for (int i = 0; i < 5000; i++) {
        int key = start_key + i;
        while (!skiplist_search(&sl, key)) {
            // Spin check until found
        }
    }
    return NULL;
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Lock-Free Skip List Stress Test...\n");
    init_skiplist(&sl);
    
    pthread_t threads[NUM_THREADS];
    int thread_ids[NUM_THREADS];
    for (int i = 0; i < NUM_THREADS; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, thread_func, &thread_ids[i]);
    }
    
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    
    if (total_inserted != 80000) {
        printf("Invariant violated: Inserted count mismatch! Expected 80000, got %d\n", total_inserted);
        return 1;
    }
    
    // Check level 0 linked list integrity
    skiplist_node *curr = atomic_load(&sl.header->next[0]);
    int count = 0;
    int prev_key = -1;
    while (curr != NULL) {
        if (curr->key <= prev_key) {
            printf("Invariant violated: Skip list out of order at key %d!\n", curr->key);
            return 1;
        }
        prev_key = curr->key;
        curr = atomic_load(&curr->next[0]);
        count++;
    }
    
    if (count != 80000) {
        printf("Invariant violated: Level 0 linked list corrupted! Expected 80000, got %d\n", count);
        return 1;
    }

    printf("FLAG: Skip List Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "SkipList-Triggered\n");
        fclose(f);
    }
    return 0;
}
