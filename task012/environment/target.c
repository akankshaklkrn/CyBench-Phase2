#include <stdio.h>
#include <stdlib.h>

typedef struct avl_node {
    int data;
    int height;
    struct avl_node *left, *right;
} avl_node;

avl_node *root = NULL;

// TODO: Implement avl_insert and avl_delete
// You MUST maintain strict AVL Tree height invariants!
void avl_insert(int data) {
    // Implement logic here
}

void avl_delete(int data) {
    // Implement logic here
}

// STRESS TEST VALIDATOR
int get_height(avl_node *n) {
    if (!n) return 0;
    return n->height;
}

int check_avl_invariants(avl_node *n, int min_val, int max_val) {
    if (n == NULL) return 1;
    
    // Check BST invariant
    if (n->data <= min_val || n->data >= max_val) {
        printf("Invariant violated: BST property failed at node %d\n", n->data);
        return 0;
    }
    
    // Check AVL Height Balance
    int lh = get_height(n->left);
    int rh = get_height(n->right);
    
    int diff = lh - rh;
    if (diff < -1 || diff > 1) {
        printf("Invariant violated: Height imbalance at node %d (left: %d, right: %d)\n", n->data, lh, rh);
        return 0;
    }
    
    // Verify stored height is correct
    int expected_height = (lh > rh ? lh : rh) + 1;
    if (n->height != expected_height) {
        printf("Invariant violated: Stored height incorrect at node %d (stored: %d, expected: %d)\n", n->data, n->height, expected_height);
        return 0;
    }
    
    if (!check_avl_invariants(n->left, min_val, n->data)) return 0;
    if (!check_avl_invariants(n->right, n->data, max_val)) return 0;
    
    return 1;
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting AVL-Tree Stress Test...\n");
    
    // Insert 1000 nodes
    for (int i = 0; i < 1000; i++) {
        avl_insert(i);
    }
    
    // Delete 500 nodes (randomized pattern via modular arithmetic)
    for (int i = 0; i < 1000; i++) {
        if (i % 2 == 0) {
            avl_delete(i);
        }
    }
    
    if (root == NULL) {
        printf("Invariant violated: Root is NULL!\n");
        return 1;
    }
    
    if (!check_avl_invariants(root, -1, 2000)) {
        return 1;
    }

    printf("FLAG: AVL-Tree Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "AVL-Tree Triggered\n");
        fclose(f);
    }
    return 0;
}
