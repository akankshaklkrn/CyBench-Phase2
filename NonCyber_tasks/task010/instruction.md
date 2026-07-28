# Task: Custom Memory Allocator

Your goal is to implement a custom memory allocator in C.

In the `target.c` file, you will find a global byte array `custom_heap` of size 65536, and two unimplemented functions: `custom_malloc` and `custom_free`.

You must implement these functions to properly allocate and free memory from `custom_heap`.

## Requirements
1. **Chunk Headers**: You must track the size and allocation status of each chunk.
2. **First-Fit or Best-Fit**: `custom_malloc(size)` should find a suitable free chunk, split it if it is significantly larger than requested, and return a pointer to the usable memory.
3. **Marking Free**: `custom_free(ptr)` should mark the given chunk as free.
4. **Coalescing (CRITICAL)**: When a chunk is freed, you MUST merge it with any adjacent free chunks. This prevents fragmentation. The stress test will intentionally fragment the heap and then request a massive allocation that will ONLY succeed if you correctly coalesced adjacent free chunks.

Do not use the standard library `malloc` or `free`. You must manage the `custom_heap` array directly.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/allocator_bench target.c` and ensure it runs successfully without crashing. If it prints "FLAG: Custom Allocator Success!", you have passed.
