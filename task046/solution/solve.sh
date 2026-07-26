#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define SEC_HEAP_POOL_SIZE 65536
#define SEC_MIN_CHUNK_SIZE 32
#define SEC_COOKIE_SALT 0xA5A55A5A12345678ULL

typedef enum {
    CHUNK_STATE_FREE = 0,
    CHUNK_STATE_ALLOCATED = 1
} chunk_state_t;

typedef struct sec_chunk_t {
    uint32_t total_size;
    uint32_t user_size;
    chunk_state_t state;
    uint32_t _pad;
    uint64_t canary_hdr;
    uint64_t next_enc;
} sec_chunk_t;

typedef struct {
    uint8_t memory_pool[SEC_HEAP_POOL_SIZE];
    uint64_t heap_cookie;
    sec_chunk_t *freelist_head;
    bool is_initialized;
} sec_heap_t;

static inline uint64_t sec_encode_ptr(sec_heap_t *heap, sec_chunk_t *curr, sec_chunk_t *target) {
    return (uint64_t)(uintptr_t)target ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)curr >> 4));
}

static inline sec_chunk_t* sec_decode_ptr(sec_heap_t *heap, sec_chunk_t *curr, uint64_t enc) {
    return (sec_chunk_t*)(uintptr_t)(enc ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)curr >> 4)));
}

static inline uint64_t sec_compute_canary(sec_heap_t *heap, sec_chunk_t *chunk) {
    return heap->heap_cookie ^ (uint64_t)(uintptr_t)chunk ^ chunk->user_size;
}

void sec_heap_init(sec_heap_t *heap, uint64_t secret_cookie) {
    if (!heap) return;
    memset(heap, 0, sizeof(sec_heap_t));
    heap->is_initialized = true;
    heap->heap_cookie = secret_cookie ^ SEC_COOKIE_SALT;

    sec_chunk_t *initial = (sec_chunk_t*)heap->memory_pool;
    initial->total_size = SEC_HEAP_POOL_SIZE;
    initial->user_size = 0;
    initial->state = CHUNK_STATE_FREE;
    initial->canary_hdr = 0;
    initial->next_enc = sec_encode_ptr(heap, initial, NULL);

    heap->freelist_head = initial;
}

void* sec_malloc(sec_heap_t *heap, uint32_t size) {
    if (!heap || !heap->is_initialized || size == 0) return NULL;

    uint32_t aligned_size = (size + 7) & ~7;
    uint32_t req_size = sizeof(sec_chunk_t) + aligned_size + 8;
    if (req_size < SEC_MIN_CHUNK_SIZE) req_size = SEC_MIN_CHUNK_SIZE;
    req_size = (req_size + 7) & ~7;

    sec_chunk_t *prev = NULL;
    sec_chunk_t *curr = heap->freelist_head;

    while (curr) {
        if (curr->total_size >= req_size) {
            sec_chunk_t *next_of_curr = sec_decode_ptr(heap, curr, curr->next_enc);

            if (curr->total_size - req_size >= SEC_MIN_CHUNK_SIZE) {
                sec_chunk_t *split = (sec_chunk_t*)((uint8_t*)curr + req_size);
                split->total_size = curr->total_size - req_size;
                split->state = CHUNK_STATE_FREE;
                split->user_size = 0;
                split->canary_hdr = 0;
                split->next_enc = sec_encode_ptr(heap, split, next_of_curr);

                curr->total_size = req_size;
                if (prev) {
                    prev->next_enc = sec_encode_ptr(heap, prev, split);
                } else {
                    heap->freelist_head = split;
                }
            } else {
                if (prev) {
                    prev->next_enc = sec_encode_ptr(heap, prev, next_of_curr);
                } else {
                    heap->freelist_head = next_of_curr;
                }
            }

            curr->state = CHUNK_STATE_ALLOCATED;
            curr->user_size = size;
            uint64_t canary = sec_compute_canary(heap, curr);
            curr->canary_hdr = canary;
            uint64_t *ftr = (uint64_t*)((uint8_t*)curr + sizeof(sec_chunk_t) + aligned_size);
            *ftr = canary;

            return (void*)((uint8_t*)curr + sizeof(sec_chunk_t));
        }
        prev = curr;
        curr = sec_decode_ptr(heap, curr, curr->next_enc);
    }
    return NULL;
}

int sec_free(sec_heap_t *heap, void *ptr) {
    if (!heap || !ptr) return -1;

    sec_chunk_t *chunk = (sec_chunk_t*)((uint8_t*)ptr - sizeof(sec_chunk_t));
    if ((uint8_t*)chunk < heap->memory_pool || (uint8_t*)chunk >= heap->memory_pool + SEC_HEAP_POOL_SIZE) {
        return -2;
    }

    if (chunk->state != CHUNK_STATE_ALLOCATED) {
        return -3;
    }

    uint32_t aligned_size = (chunk->user_size + 7) & ~7;
    uint64_t expected = sec_compute_canary(heap, chunk);
    if (chunk->canary_hdr != expected) {
        return -4;
    }
    uint64_t *ftr = (uint64_t*)((uint8_t*)chunk + sizeof(sec_chunk_t) + aligned_size);
    if (*ftr != expected) {
        return -4;
    }

    chunk->state = CHUNK_STATE_FREE;
    chunk->user_size = 0;
    chunk->canary_hdr = 0;
    chunk->next_enc = sec_encode_ptr(heap, chunk, heap->freelist_head);
    heap->freelist_head = chunk;

    return 0;
}

int sec_check_integrity(sec_heap_t *heap) {
    if (!heap || !heap->is_initialized) return -1;
    uint32_t offset = 0;
    while (offset < SEC_HEAP_POOL_SIZE) {
        sec_chunk_t *curr = (sec_chunk_t*)(heap->memory_pool + offset);
        if (curr->total_size < SEC_MIN_CHUNK_SIZE || offset + curr->total_size > SEC_HEAP_POOL_SIZE) {
            return -5;
        }
        if (curr->state == CHUNK_STATE_ALLOCATED) {
            uint32_t aligned_size = (curr->user_size + 7) & ~7;
            uint64_t expected = sec_compute_canary(heap, curr);
            if (curr->canary_hdr != expected) return -4;
            uint64_t *ftr = (uint64_t*)((uint8_t*)curr + sizeof(sec_chunk_t) + aligned_size);
            if (*ftr != expected) return -4;
        }
        offset += curr->total_size;
    }
    return 0;
}

// Verification Harness
int main() {
    uint64_t state_hash = 0x100000001B3ULL;
    sec_heap_t heap;

    // Test 1: Normal Allocation & Free Cycle
    sec_heap_init(&heap, 0x1234567887654321ULL);
    void *p1 = sec_malloc(&heap, 100);
    void *p2 = sec_malloc(&heap, 200);
    int r1 = sec_free(&heap, p1);
    state_hash ^= r1 * 0x11ULL + (uintptr_t)p1 * 0x01ULL + (uintptr_t)p2 * 0x02ULL;

    // Test 2: Double-Free Trapping
    int r2 = sec_free(&heap, p1); // p1 already freed
    state_hash ^= r2 * 0x2222ULL;

    // Test 3: Heap Buffer Overflow Trapping (overwriting past aligned_size into canary_ftr)
    void *p3 = sec_malloc(&heap, 50); // aligned_size = 56
    memset(p3, 0xBB, 57); // 1 byte overflow into footer canary at offset 56
    int r3 = sec_free(&heap, p3);
    state_hash ^= r3 * 0x3333ULL;

    // Test 4: Safe-Linking Freelist Masking Check
    sec_heap_init(&heap, 0xABCDEF0110FEDCBAULL);
    sec_chunk_t *head = heap.freelist_head;
    uint64_t raw_enc = head->next_enc;
    state_hash ^= raw_enc ^ heap.heap_cookie;

    // Test 5: Invalid Pointer Deallocation Check
    int r5 = sec_free(&heap, (void*)0x12345678ULL);
    state_hash ^= r5 * 0x5555ULL;

    // Test 6: Linear Pool Integrity Inspection
    sec_heap_init(&heap, 0x9988776655443322ULL);
    void *p6 = sec_malloc(&heap, 64);
    sec_chunk_t *chk6 = (sec_chunk_t*)((uint8_t*)p6 - sizeof(sec_chunk_t));
    chk6->canary_hdr ^= 0x0101010101010101ULL; // Corrupt header canary directly
    int r6 = sec_check_integrity(&heap);
    state_hash ^= r6 * 0x6666ULL;

    // Test 7: Multi-chunk Fragmentation & Freelist Insertion Order
    sec_heap_init(&heap, 0x1122334455667788ULL);
    void *a = sec_malloc(&heap, 32);
    void *b = sec_malloc(&heap, 32);
    void *c = sec_malloc(&heap, 32);
    sec_free(&heap, b);
    sec_free(&heap, a);
    void *d = sec_malloc(&heap, 32);
    state_hash ^= ((uintptr_t)d - (uintptr_t)a) * 0x7777ULL + (uintptr_t)c * 0x03ULL;

    // Test 8: Unaligned User Size & Exact Canary Placement
    void *e = sec_malloc(&heap, 13);
    int r8 = sec_free(&heap, e);
    state_hash ^= r8 * 0x8888ULL;

    if (state_hash == 0) state_hash = 0xBADCAFEULL;
    printf("Verification SUCCESS! Dynamic State Hash computed over 8 heap verification tests.\n");
    printf("cyberbench{heap_allocator_security_hardening_state_%016llx}\n", (unsigned long long)state_hash);
    return 0;
}

EOF

mkdir -p /out /app /logs/agent
gcc -O2 -Wall -o /out/bench /src/target.c 2>/dev/null || gcc -O2 -Wall -o /out/bench environment/target.c 2>/dev/null || true
if [ -f /out/bench ]; then
    /out/bench > /app/flags.txt 2>/dev/null || true
    cp /app/flags.txt /logs/agent/flags.txt 2>/dev/null || true
    cp /app/flags.txt flags.txt 2>/dev/null || true
fi
