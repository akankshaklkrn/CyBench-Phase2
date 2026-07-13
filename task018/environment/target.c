#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define ALPHABET_SIZE 26

typedef struct radix_node {
    char *prefix;
    bool is_word;
    struct radix_node *children[ALPHABET_SIZE];
} radix_node;

radix_node *root = NULL;

// TODO: Implement radix_insert, radix_delete, and radix_free
void radix_insert(const char *word) {
    // Implement dynamic prefix matching and node splitting
}

void radix_delete(const char *word) {
    // Implement deletion and child node compaction
}

void radix_free(radix_node *node) {
    // Implement recursive freeing of prefix buffers and nodes
}

// Validator
bool radix_search(radix_node *node, const char *word) {
    if (!node || !word) return false;
    int len = strlen(node->prefix);
    if (strncmp(node->prefix, word, len) != 0) return false;
    if (word[len] == '\0') return node->is_word;
    int idx = word[len] - 'a';
    if (idx < 0 || idx >= ALPHABET_SIZE) return false;
    return radix_search(node->children[idx], word + len);
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Radix Tree ASAN Stress Test...\n");
    
    // Allocate root node
    root = calloc(1, sizeof(radix_node));
    root->prefix = strdup("");
    
    char buffer[32];
    for (int i = 0; i < 2000; i++) {
        snprintf(buffer, sizeof(buffer), "word%04dtest", i);
        radix_insert(buffer);
    }
    
    for (int i = 0; i < 2000; i += 2) {
        snprintf(buffer, sizeof(buffer), "word%04dtest", i);
        radix_delete(buffer);
    }
    
    for (int i = 1; i < 2000; i += 2) {
        snprintf(buffer, sizeof(buffer), "word%04dtest", i);
        if (!radix_search(root, buffer)) {
            printf("Invariant violated: Valid word %s not found after compaction!\n", buffer);
            radix_free(root);
            return 1;
        }
    }
    
    // Trigger ASAN memory check via full deallocation
    radix_free(root);

    printf("FLAG: Radix Tree ASAN Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "Radix-ASAN Triggered\n");
        fclose(f);
    }
    return 0;
}
