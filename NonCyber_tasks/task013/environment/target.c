#include <stdio.h>
#include <stdlib.h>
#include <stdbool.h>

#define ORDER 4

typedef struct bplus_node {
    bool is_leaf;
    int num_keys;
    int keys[ORDER];
    struct bplus_node *pointers[ORDER + 1];
    struct bplus_node *next; // Only used if is_leaf == true
} bplus_node;

bplus_node *root = NULL;

// TODO: Implement bplus_insert and bplus_delete
void bplus_insert(int data) {
    // Implement logic here
}

void bplus_delete(int data) {
    // Implement logic here
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting B+ Tree Stress Test...\n");
    
    // Insert 10000 nodes
    for (int i = 0; i < 10000; i++) {
        bplus_insert(i);
    }
    
    // Delete 5000 nodes
    for (int i = 0; i < 10000; i += 2) {
        bplus_delete(i);
    }
    
    if (root == NULL) {
        printf("Invariant violated: Root is NULL!\n");
        return 1;
    }
    
    // Verify leaf linked list
    bplus_node *curr = root;
    while (!curr->is_leaf) {
        curr = curr->pointers[0];
    }
    
    int expected = 1;
    int count = 0;
    while (curr != NULL) {
        for (int i = 0; i < curr->num_keys; i++) {
            if (curr->keys[i] != expected) {
                printf("Invariant violated: Leaf linked list out of order or corrupted! Expected %d, got %d\n", expected, curr->keys[i]);
                return 1;
            }
            expected += 2;
            count++;
        }
        curr = curr->next;
    }
    
    if (count != 5000) {
        printf("Invariant violated: Leaf linked list count mismatch! Expected 5000, got %d\n", count);
        return 1;
    }

    printf("FLAG: B+ Tree Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "BPlus-Tree Triggered\n");
        fclose(f);
    }
    return 0;
}
