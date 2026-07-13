#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <stdbool.h>

#define RED true
#define BLACK false
#define NUM_THREADS 16
#define ITEMS_PER_THREAD 1250

typedef struct llrb_node {
    int key;
    bool color;
    struct llrb_node *left, *right;
    pthread_mutex_t lock;
} llrb_node;

llrb_node *root = NULL;
pthread_rwlock_t root_rwlock = PTHREAD_RWLOCK_INITIALIZER;

// TODO: Implement concurrent llrb_insert and llrb_search with proper mutex/rwlock synchronization
void llrb_insert(int key) {
    // Implement concurrent LLRB insertion with left-leaning rotations and color flips
}

bool llrb_search(int key) {
    // Implement concurrent search
    return false;
}

void* thread_func(void* arg) {
    int id = *(int*)arg;
    int start = id * ITEMS_PER_THREAD;
    for (int i = 0; i < ITEMS_PER_THREAD; i++) {
        llrb_insert(start + i);
    }
    for (int i = 0; i < ITEMS_PER_THREAD; i++) {
        while (!llrb_search(start + i)) {
            // Spin until key is found
        }
    }
    return NULL;
}

// Validator
int check_llrb_invariants(llrb_node *n, int min_val, int max_val, int *black_height) {
    if (n == NULL) {
        *black_height = 0;
        return 1;
    }
    if (n->key <= min_val || n->key >= max_val) {
        printf("Invariant violated: BST property failed at key %d\n", n->key);
        return 0;
    }
    // Check right-leaning red link
    if (n->right && n->right->color == RED && (!n->left || n->left->color == BLACK)) {
        printf("Invariant violated: Right-leaning red link at key %d!\n", n->key);
        return 0;
    }
    // Check two consecutive red links
    if (n->color == RED && n->left && n->left->color == RED) {
        printf("Invariant violated: Two consecutive red links at key %d!\n", n->key);
        return 0;
    }
    
    int left_bh, right_bh;
    if (!check_llrb_invariants(n->left, min_val, n->key, &left_bh) ||
        !check_llrb_invariants(n->right, n->key, max_val, &right_bh)) {
        return 0;
    }
    if (left_bh != right_bh) {
        printf("Invariant violated: Black-height mismatch at key %d! Left: %d, Right: %d\n",
               n->key, left_bh, right_bh);
        return 0;
    }
    *black_height = left_bh + (n->color == BLACK ? 1 : 0);
    return 1;
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Concurrent LLRB Tree TSAN Stress Test...\n");
    
    pthread_t threads[NUM_THREADS];
    int thread_ids[NUM_THREADS];
    for (int i = 0; i < NUM_THREADS; i++) {
        thread_ids[i] = i;
        pthread_create(&threads[i], NULL, thread_func, &thread_ids[i]);
    }
    for (int i = 0; i < NUM_THREADS; i++) {
        pthread_join(threads[i], NULL);
    }
    
    int bh;
    if (root == NULL || !check_llrb_invariants(root, -1, 100000, &bh)) {
        return 1;
    }

    printf("FLAG: LLRB TSAN Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "LLRB-TSAN Triggered\n");
        fclose(f);
    }
    return 0;
}
