# Task: Lock-Free Concurrent Queue

Your goal is to implement a Lock-Free Queue in C using C11 `<stdatomic.h>`.

In the `target.c` file, you will find the basic node struct and the global queue structure containing atomic head and tail pointers.
You must implement two functions: `enqueue` and `dequeue`.

## Requirements
1. **No Locks allowed**: You must use raw atomic operations (e.g., `atomic_compare_exchange_weak`, `atomic_load`) to manipulate the pointers. You cannot use mutexes or spinlocks.
2. **Michael-Scott Algorithm**: Implement the standard lock-free queue algorithm where both the `next` pointers and the `tail` pointer are advanced atomically.
3. **ABA Problem handling**: Since you are operating in a highly concurrent environment, you must handle standard lock-free hazards. (For simplicity in this task, nodes are never freed during the test to avoid full hazard pointers, but the atomic insertions must be perfectly ordered).

The stress test will spawn 16 concurrent threads. Each thread will push 10,000 items and then pop 10,000 items. If your atomic logic contains any race conditions, the program will segfault, deadlock, or drop items.

When you are done, compile the code using `gcc -O3 -Wall -pthread -Werror -o /out/queue_bench target.c` and ensure it runs successfully. If it prints "FLAG: Queue Success!", you have passed.
