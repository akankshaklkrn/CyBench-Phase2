#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define HEAP_SIZE 65536
char custom_heap[HEAP_SIZE];

// TODO: Implement custom_malloc and custom_free
// Requirements:
// 1. Must track chunk sizes and whether they are free.
// 2. custom_malloc(size) should return a pointer to an appropriately sized free chunk.
// 3. custom_free(ptr) should mark the chunk as free.
// 4. MUST implement coalescing: adjacent free chunks must be merged to prevent fragmentation!

void* custom_malloc(size_t size) {
    // Implement logic here
    return NULL;
}

void custom_free(void* ptr) {
    // Implement logic here
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting Allocator Stress Test...\n");

    // Test 1: Basic allocations
    void* a = custom_malloc(1024);
    void* b = custom_malloc(2048);
    void* c = custom_malloc(4096);
    
    if (!a || !b || !c) {
        printf("Failed basic allocation!\n");
        return 1;
    }
    if (a == b || b == c || a == c) {
        printf("Pointers overlap!\n");
        return 1;
    }
    
    // Test 2: Write data and ensure no corruption
    memset(a, 'A', 1024);
    memset(b, 'B', 2048);
    memset(c, 'C', 4096);
    
    for (int i = 0; i < 1024; i++) if (((char*)a)[i] != 'A') { printf("Corruption in a\n"); return 1; }
    for (int i = 0; i < 2048; i++) if (((char*)b)[i] != 'B') { printf("Corruption in b\n"); return 1; }
    for (int i = 0; i < 4096; i++) if (((char*)c)[i] != 'C') { printf("Corruption in c\n"); return 1; }
    
    // Test 3: Free and Coalesce
    custom_free(b);
    custom_free(a);
    custom_free(c);
    
    // If coalescing worked perfectly, we should be able to allocate almost the entire heap size again
    // We leave a small margin for header metadata (e.g. 100 bytes)
    void* huge = custom_malloc(HEAP_SIZE - 100);
    if (!huge) {
        printf("Failed to allocate huge chunk. Coalescing is not implemented or broken!\n");
        return 1;
    }
    
    memset(huge, 'X', HEAP_SIZE - 100);
    for (int i = 0; i < (HEAP_SIZE - 100); i++) if (((char*)huge)[i] != 'X') { printf("Corruption in huge chunk\n"); return 1; }

    printf("FLAG: Custom Allocator Success!\n");
    FILE *f = fopen("/tmp/success.txt", "w");
    if (f) {
        fprintf(f, "Custom Allocator Triggered\n");
        fclose(f);
    }
    return 0;
}
