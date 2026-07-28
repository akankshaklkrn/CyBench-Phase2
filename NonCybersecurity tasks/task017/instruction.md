# Task: Lock-Free Concurrent Stack with Hazard Pointers

Your goal is to implement a Lock-Free Stack (Treiber Stack) in C using C11 `<stdatomic.h>` with **Hazard Pointers** for safe memory reclamation.

In `target.c`, you are given node definitions, a stack structure, and a basic hazard pointer array for up to 16 threads.
You must implement `push(stack_t *s, int value)` and `pop(stack_t *s, int *value, int thread_id)`.

## Requirements
1. **Treiber Stack Algorithm**: Implement lock-free push and pop using `atomic_compare_exchange_weak`. No mutexes or locks allowed.
2. **Hazard Pointers**: When a thread attempts to pop a node, it must set its slot in the global `hazard_pointers[thread_id]` array to the target node before dereferencing it. This prevents other threads from reclaiming or corrupting memory while it is being read.
3. **Safe Reclamation**: Nodes popped from the stack can only be freed if no thread currently holds a hazard pointer to them.

The stress test will spawn 16 concurrent threads simultaneously pushing and popping 200,000 items. If your hazard pointers or atomic barriers are incorrect, the test will experience race conditions, ABA hazards, double-frees, or segfaults.

When you are done, compile the code using `gcc -O3 -Wall -pthread -Werror -o /out/stack_bench target.c` and ensure it runs successfully. If it prints "FLAG: Hazard Stack Success!", you have passed.
