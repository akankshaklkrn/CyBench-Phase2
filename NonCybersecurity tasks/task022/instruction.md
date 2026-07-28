# Task: Concurrent Left-Leaning Red-Black (LLRB) Tree with ThreadSanitizer

Your goal is to implement a Concurrent Left-Leaning Red-Black Tree in C, compiled with ThreadSanitizer (`-fsanitize=thread`).

In `target.c`, you are given an `llrb_node` struct that contains an integer `key`, a boolean color flag (`RED` or `BLACK`), left/right child pointers, and a `pthread_mutex_t lock`.
You must implement `llrb_insert(int key)` and `llrb_search(int key)`.

## Requirements
1. **Left-Leaning Red-Black Invariants**:
   - Red links must only lean left (a right child cannot be RED if the left child is BLACK).
   - No two RED links can be sequential (a RED node cannot have a RED child).
   - Perfect black-height balance: Every path from the root down to a NULL leaf must contain the exact same number of BLACK nodes.
2. **Fine-Grained Concurrency**: You must use hand-over-hand mutex locking or node-level locking during traversal, insertions, rotations, and color flips so that multiple threads can safely interact with the tree.
3. **ThreadSanitizer Safety**: This task is compiled with `-fsanitize=thread`. If your locking logic misses a synchronization barrier during a rotation or color flip, ThreadSanitizer will detect a data race and abort execution. If you introduce lock ordering errors, it will deadlock.

The stress test will spawn 16 concurrent threads inserting and searching for 20,000 items simultaneously, followed by an exhaustive invariant verification of the entire tree structure.

When you are done, compile the code using `gcc -O2 -Wall -Werror -pthread -fsanitize=thread -o /out/llrb_bench target.c` and ensure it runs successfully. If it prints "FLAG: LLRB TSAN Success!", you have passed.
