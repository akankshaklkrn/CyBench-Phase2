# Task: Lock-Free Concurrent Skip List

Your goal is to implement a Lock-Free Concurrent Skip List in C using C11 `<stdatomic.h>`.

In the `target.c` file, you will find a `skiplist_node` struct with an atomic `next` pointer array across multiple probabilistic levels, and the global skip list header.
You must implement two lock-free functions: `skiplist_insert(skiplist_t *sl, int key, int top_level)` and `skiplist_search(skiplist_t *sl, int key)`.

## Requirements
1. **No Locks Allowed**: You must use raw C11 atomic operations (`atomic_compare_exchange_weak`, `atomic_load`, `atomic_store`). You cannot use mutexes or spinlocks.
2. **Multi-Level Splicing**: When inserting a node with level $L$, you must atomically splice it into all levels from $0$ up to $L$.
3. **Concurrent Search**: `skiplist_search` must traverse the levels from top to bottom lock-free and return true if the key exists.

The stress test will spawn 16 concurrent threads simultaneously inserting and searching for 100,000 items across 8 levels. If your atomic level-linking logic contains any race conditions, the list will corrupt, drop nodes, or deadlock.

When you are done, compile the code using `gcc -O3 -Wall -pthread -Werror -o /out/skiplist_bench target.c` and ensure it runs successfully. If it prints "FLAG: Skip List Success!", you have passed.
