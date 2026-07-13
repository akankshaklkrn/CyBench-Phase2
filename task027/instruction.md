# Task: Custom Buddy Memory Allocator with Recursive Coalescing

Your goal is to implement a power-of-two **Buddy Memory Allocator** in C targeting Linux.

In `target.c`, you are given a pre-allocated raw memory pool of 16 MB (`POOL_SIZE = 16 * 1024 * 1024`) with minimum block size of 64 bytes (`MIN_BLOCK_SIZE = 64`).

You must implement:
1. `void buddy_init(void *pool, size_t pool_size)`: Initialize the free lists for orders $0$ to $N$.
2. `void *buddy_malloc(size_t size)`: Allocate memory by finding the smallest power-of-two block order that satisfies `size`. If no block of that exact order is available, you must recursively **split** a larger block into two equal halves ("buddies") until the target order is reached.
3. `void buddy_free(void *ptr)`: Free an allocated memory block. You must calculate the exact memory address of its companion buddy using bitwise XOR (`buddy_addr = ((uintptr_t)ptr - (uintptr_t)pool) ^ block_size + (uintptr_t)pool`). If the companion buddy is currently free and in the same order class, you must remove it from the free list and **recursively coalesce (merge)** the two buddies into a higher-order block, repeating until no further coalescing is possible!

## Requirements
- **Recursive Coalescing**: When freeing memory, you must coalesce buddies recursively. If freeing blocks leaves fragmented non-coalesced buddies in memory, the fragmentation test will fail.
- **No Memory Corruption**: Compiled with AddressSanitizer (`-fsanitize=address`) and UndefinedBehaviorSanitizer (`-fsanitize=undefined`). Any out-of-bounds access, dangling pointer in free lists, or double free will abort the test.
- **Zero Leakage & Perfect Recovery**: After executing 10,000 randomized allocations and frees, the entire pool must coalesce back to a single 16 MB free block.

When finished, compile your code using `gcc -O2 -Wall -Werror -fsanitize=address,undefined -o /out/buddy_bench target.c` and verify it outputs "FLAG: Buddy Memory Allocator Recursive Coalescing Success!".
