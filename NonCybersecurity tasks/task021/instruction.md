# Task: Bounded Ring Buffer with ThreadSanitizer & UndefinedBehaviorSanitizer

Your goal is to implement a high-performance concurrent Bounded Ring Buffer (Circular Queue) in C for multiple producer and consumer threads.

In `target.c`, you are given a circular buffer structure with atomic head and tail indices.
You must implement `ring_push(ring_buffer_t *rb, int value)` and `ring_pop(ring_buffer_t *rb, int *value)`.

## Requirements
1. **No Mutexes**: Implement push and pop lock-free using atomic compare-exchange and explicit memory ordering barriers (`memory_order_acquire`, `memory_order_release`).
2. **Strict Concurrency Safety (TSAN + UBSAN)**: This task is compiled with `-fsanitize=thread,undefined`. If your implementation introduces even a microscopic data race between producer and consumer threads due to missing memory fences, or performs an out-of-bounds array access, ThreadSanitizer/UBSAN will abort the program immediately.
3. **Bounded Capacity**: If the buffer is full, `ring_push` must spin/wait lock-free until space is available. If empty, `ring_pop` must spin/wait lock-free until an item is produced.

The stress test will spawn 8 producer threads pushing 250,000 items each, and 8 consumer threads popping 250,000 items each simultaneously over a buffer of capacity 1024.

When you are done, compile the code using `gcc -O3 -Wall -Werror -pthread -fsanitize=thread,undefined -o /out/ring_bench target.c` and ensure it runs successfully. If it prints "FLAG: Ring Buffer TSAN Success!", you have passed.
