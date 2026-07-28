#include <stdio.h>
#include <stdlib.h>

typedef struct splay_node {
    int key;
    struct splay_node *left, *right, *parent;
} splay_node;

splay_node *root = NULL;

// TODO: Implement splay, splay_insert, and splay_delete
void splay(splay_node *n) {
    // Implement zig, zig-zig, zig-zag rotations to bring n to root
}

void splay_insert(int key) {
    // Implement insertion and then splay the new node to root
}

void splay_delete(int key) {
    // Implement deletion in a splay tree
}

// BST Validator
int check_bst(splay_node *n, int min_val, int max_val) {
    if (n == NULL) return 1;
    if (n->key <= min_val || n->key >= max_val) {
        printf("Invariant violated: BST property failed at key %d\n", n->key);
        return 0;
    }
    if (n->left && n->left->parent != n) {
        printf("Invariant violated: Parent pointer mismatch at key %d (left child)\n", n->key);
        return 0;
    }
    if (n->right && n->right->parent != n) {
        printf("Invariant violated: Parent pointer mismatch at key %d (right child)\n", n->key);
        return 0;
    }
    return check_bst(n->left, min_val, n->key) && check_bst(n->right, n->key, max_val);
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Splay Tree Stress Test...\n");
    
    // Insert 5000 nodes
    for (int i = 0; i < 5000; i++) {
        splay_insert(i);
        if (root == NULL || root->key != i) {
            printf("Invariant violated: Newly inserted key %d is not at root!\n", i);
            return 1;
        }
        if (i % 500 == 0 && !check_bst(root, -1, 10000)) {
            return 1;
        }
    }
    
    // Delete 2500 nodes
    for (int i = 0; i < 5000; i += 2) {
        splay_delete(i);
    }
    
    if (root == NULL) {
        printf("Invariant violated: Root is NULL after deletion!\n");
        return 1;
    }
    
    if (!check_bst(root, -1, 10000)) {
        return 1;
    }

    printf("FLAG: Splay Tree Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "Splay-Tree Triggered\n");
        fclose(f);
    }
    return 0;
}
