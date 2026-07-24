#include <stdio.h>
#include <stdlib.h>

typedef struct treap_node {
    int key;
    int priority;
    struct treap_node *left, *right;
} treap_node;

treap_node *root = NULL;

// TODO: Implement treap_insert and treap_delete
// You MUST maintain both BST (key) and Max-Heap (priority) invariants!
void treap_insert(int key, int priority) {
    // Implement BST insertion followed by heap-restoring rotations
}

void treap_delete(int key) {
    // Implement downward rotation to leaf followed by deletion
}

// Validator
int check_treap_invariants(treap_node *n, int min_key, int max_key) {
    if (n == NULL) return 1;
    
    // 1. Check BST invariant on key
    if (n->key <= min_key || n->key >= max_key) {
        printf("Invariant violated: BST property failed at key %d!\n", n->key);
        return 0;
    }
    
    // 2. Check Max-Heap invariant on priority
    if (n->left && n->left->priority > n->priority) {
        printf("Invariant violated: Heap priority failed! Parent key %d (prio %d) < Left child key %d (prio %d)\n",
               n->key, n->priority, n->left->key, n->left->priority);
        return 0;
    }
    if (n->right && n->right->priority > n->priority) {
        printf("Invariant violated: Heap priority failed! Parent key %d (prio %d) < Right child key %d (prio %d)\n",
               n->key, n->priority, n->right->key, n->right->priority);
        return 0;
    }
    
    return check_treap_invariants(n->left, min_key, n->key) &&
           check_treap_invariants(n->right, n->key, max_key);
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Treap Dual-Invariant Stress Test...\n");
    
    // Insert 5000 nodes with deterministic pseudo-random priorities
    for (int i = 0; i < 5000; i++) {
        int prio = (i * 2654435761u) % 1000000;
        treap_insert(i, prio);
    }
    
    if (root == NULL) {
        printf("Invariant violated: Root is NULL after insertion!\n");
        return 1;
    }
    if (!check_treap_invariants(root, -1, 10000)) {
        return 1;
    }
    
    // Delete 2500 nodes
    for (int i = 0; i < 5000; i += 2) {
        treap_delete(i);
    }
    
    if (root == NULL) {
        printf("Invariant violated: Root is NULL after deletion!\n");
        return 1;
    }
    
    if (!check_treap_invariants(root, -1, 10000)) {
        return 1;
    }

    printf("FLAG: Treap Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "Treap-Triggered\n");
        fclose(f);
    }
    return 0;
}
