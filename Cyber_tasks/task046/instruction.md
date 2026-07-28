# Level 0 Challenge: Hardened Secure Heap Allocator (`heap_allocator_security_hardening_l0`)

You are tasked with implementing a **Secure Heap Memory Allocator & Exploit Mitigation Engine** inside a high-concurrency runtime. Modern memory allocators protect user applications against heap corruption vulnerabilities (`use-after-free`, `double-free`, `buffer overflow`, and `freelist poisoning`) by enforcing strict structural invariants, inline header and footer canaries, and safe-linking pointer masking. Any flaw in chunk metadata management or integrity verification allows attacker exploitation of the memory subsystem.

## System Specification

The memory subsystem manages a fixed memory pool (`memory_pool[65536]`) divided into chunks (`sec_chunk_t`) organized across a singly linked freelist (`freelist_head`).

### 1. Memory & Chunk Structures

```c
#define SEC_HEAP_POOL_SIZE 65536
#define SEC_MIN_CHUNK_SIZE 32
#define SEC_COOKIE_SALT 0xA5A55A5A12345678ULL

typedef enum {
    CHUNK_STATE_FREE = 0,
    CHUNK_STATE_ALLOCATED = 1
} chunk_state_t;

typedef struct {
    uint32_t total_size;       // Total size of this block in bytes (including this header and footer canary)
    uint32_t user_size;        // Requested user size (must be <= total_size - sizeof(sec_chunk_t) - 8)
    chunk_state_t state;       // CHUNK_STATE_FREE or CHUNK_STATE_ALLOCATED
    uint32_t _pad;
    uint64_t canary_hdr;       // Header canary value right before user data
    uint64_t next_enc;         // Safe-linked XOR-masked pointer to next free block (only valid when FREE)
    // Followed by `aligned_user_size` bytes of user payload
    // Followed by 8-byte `canary_ftr` footer canary (aligned on 8-byte boundary)
} sec_chunk_t;

typedef struct {
    uint8_t memory_pool[SEC_HEAP_POOL_SIZE];
    uint64_t heap_cookie;      // Random 64-bit secret cookie for safe-linking and canary generation
    sec_chunk_t *freelist_head;
    bool is_initialized;
} sec_heap_t;
```

### 2. Safe-Linking & Canary Mechanics

To prevent freelist pointer manipulation exploits (`freelist poisoning`):
- When storing a pointer `ptr` (to the next `sec_chunk_t*`) inside `chunk->next_enc`, compute:
  `chunk->next_enc = (uint64_t)(uintptr_t)ptr ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)chunk >> 4));`
  (If `ptr == NULL`, `chunk->next_enc = 0 ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)chunk >> 4))`).
- When reading `chunk->next_enc` to retrieve the next `sec_chunk_t*` pointer, compute:
  `sec_chunk_t *next = (sec_chunk_t*)(uintptr_t)(chunk->next_enc ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)chunk >> 4)));`

To detect buffer overflows (`heap overflow`):
- Compute 8-byte aligned payload length: `uint32_t aligned_size = (chunk->user_size + 7) & ~7;`
- When allocating a chunk, set both `canary_hdr` and the 8-byte `canary_ftr` (located at `(uint64_t*)((uint8_t*)chunk + sizeof(sec_chunk_t) + aligned_size)`) to:
  `uint64_t expected_canary = heap->heap_cookie ^ (uint64_t)(uintptr_t)chunk ^ chunk->user_size;`
- During `sec_free` and `sec_check_integrity`, verify that both `canary_hdr` and `canary_ftr` exactly match this expected value.

### 3. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void sec_heap_init(sec_heap_t *heap, uint64_t secret_cookie)`
Initializes the secure heap allocator:
- Sets `heap->is_initialized = true` and `heap->heap_cookie = secret_cookie ^ SEC_COOKIE_SALT`.
- Initializes a single initial free block starting at `(sec_chunk_t*)heap->memory_pool`:
  - `total_size = SEC_HEAP_POOL_SIZE`
  - `user_size = 0`
  - `state = CHUNK_STATE_FREE`
  - `canary_hdr = 0`
  - Safe-links `next_enc` to `NULL` (`0 ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)initial_chunk >> 4))`).
- Sets `heap->freelist_head` to point to this initial block.

#### `void* sec_malloc(sec_heap_t *heap, uint32_t size)`
Allocates hardened memory of requested `size` bytes:
- If `!heap || !heap->is_initialized || size == 0`, return `NULL`.
- Align `size` up to the nearest multiple of `8` (`aligned_size = (size + 7) & ~7`).
- Compute required block size: `req_size = sizeof(sec_chunk_t) + aligned_size + 8` (header + aligned user bytes + footer canary).
- Ensure `req_size` is at least `SEC_MIN_CHUNK_SIZE` and aligned (`req_size = (req_size + 7) & ~7`).
- Traverse `heap->freelist_head` (using safe-linking decoding) to find the first free block where `curr->total_size >= req_size`.
- If no block found, return `NULL`.
- **Block Splitting**: If `curr->total_size - req_size >= SEC_MIN_CHUNK_SIZE`:
  - Split `curr`: create a new free chunk `split_chunk` at `(uint8_t*)curr + req_size`.
  - `split_chunk->total_size = curr->total_size - req_size`, `split_chunk->state = CHUNK_STATE_FREE`, `split_chunk->user_size = 0`.
  - Safe-link `split_chunk->next_enc` to point to whatever `curr` pointed to (`next_of_curr`).
  - Update `curr->total_size = req_size`.
  - Replace `curr` with `split_chunk` in the freelist (either updating `heap->freelist_head` or the previous chunk's `next_enc`).
- If `curr->total_size - req_size < SEC_MIN_CHUNK_SIZE`, do not split (`curr` keeps its entire `total_size`), but remove `curr` from the freelist.
- Set `curr->state = CHUNK_STATE_ALLOCATED` and `curr->user_size = size` (store the exact requested user size for canary calculations).
- Compute and set `canary_hdr` and `canary_ftr` (`at (uint64_t*)((uint8_t*)curr + sizeof(sec_chunk_t) + aligned_size)`) using the canary formula.
- Return pointer to user payload: `(void*)((uint8_t*)curr + sizeof(sec_chunk_t))`.

#### `int sec_free(sec_heap_t *heap, void *ptr)`
Frees an allocated memory block and verifies integrity:
- If `!heap || !ptr`, return `-1` (`SEC_ERR_INVALID_ARG`).
- Compute chunk header address: `sec_chunk_t *chunk = (sec_chunk_t*)((uint8_t*)ptr - sizeof(sec_chunk_t))`.
- **Bounds Check**: Verify `(uint8_t*)chunk >= heap->memory_pool && (uint8_t*)chunk < heap->memory_pool + SEC_HEAP_POOL_SIZE`. If out of bounds, return `-2` (`SEC_ERR_INVALID_PTR`).
- **Double-Free Check**: Verify `chunk->state == CHUNK_STATE_ALLOCATED`. If `chunk->state == CHUNK_STATE_FREE`, immediately trap and return `-3` (`SEC_ERR_DOUBLE_FREE`).
- **Canary & Overflow Verification**:
  - Compute `aligned_size = (chunk->user_size + 7) & ~7`.
  - Compute `expected_canary = heap->heap_cookie ^ (uint64_t)(uintptr_t)chunk ^ chunk->user_size`.
  - Check `chunk->canary_hdr == expected_canary`.
  - Check `*(uint64_t*)((uint8_t*)chunk + sizeof(sec_chunk_t) + aligned_size) == expected_canary`.
  - If either canary does not match, return `-4` (`SEC_ERR_HEAP_OVERFLOW`).
- Mark `chunk->state = CHUNK_STATE_FREE`, `chunk->user_size = 0`, `chunk->canary_hdr = 0`.
- Insert `chunk` at the head of `heap->freelist_head` using safe-linking encoding:
  `chunk->next_enc = (uint64_t)(uintptr_t)heap->freelist_head ^ (heap->heap_cookie ^ ((uint64_t)(uintptr_t)chunk >> 4));`
  `heap->freelist_head = chunk;`
- Return `0` on success.

#### `int sec_check_integrity(sec_heap_t *heap)`
Scans all chunks across `heap->memory_pool` from offset `0` to `SEC_HEAP_POOL_SIZE` to verify that no allocated chunk has suffered overflow or metadata corruption:
- Traverse linearly from `(sec_chunk_t*)heap->memory_pool` while `offset < SEC_HEAP_POOL_SIZE`:
  - If `curr->total_size < SEC_MIN_CHUNK_SIZE` or `offset + curr->total_size > SEC_HEAP_POOL_SIZE`, return `-5` (`SEC_ERR_CORRUPT_METADATA`).
  - If `curr->state == CHUNK_STATE_ALLOCATED`:
    - Compute `aligned_size = (curr->user_size + 7) & ~7`.
    - Compute `expected = heap->heap_cookie ^ (uint64_t)(uintptr_t)curr ^ curr->user_size`.
    - Verify `curr->canary_hdr == expected` and `*(uint64_t*)((uint8_t*)curr + sizeof(sec_chunk_t) + aligned_size) == expected`. If mismatch, return `-4` (`SEC_ERR_HEAP_OVERFLOW`).
  - Advance `offset += curr->total_size`.
- Return `0` if entire pool verified cleanly.

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) simulating 8 rigorous memory exploit scenarios:
1. Normal Allocation, Block Splitting, & Deallocation Cycle.
2. Double-Free Trapping (`sec_free` called twice on the same pointer).
3. Heap Buffer Overflow Trapping (overwriting past `aligned_size` into `canary_ftr`).
4. Safe-Linking Freelist Pointer Masking Integrity Check (verifying `next_enc` is properly XOR-masked).
5. Invalid Pointer Deallocation Check (`sec_free` called on arbitrary stack/heap address).
6. Linear Pool Integrity Inspection (`sec_check_integrity` detecting corrupted `canary_hdr`).
7. Multi-chunk Fragmentation & Freelist Insertion Order Verification.
8. Unaligned User Size Allocation & Exact Canary Placement Check (`size = 13` vs `aligned_size = 16`).

If your allocator accurately traps all corruption attempts without ASAN violations, the driver outputs:
```
cyberbench{heap_allocator_security_hardening_state_<64-bit-hex-hash>}
```
