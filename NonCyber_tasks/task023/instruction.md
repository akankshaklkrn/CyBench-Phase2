# Task: Standalone Hazard Pointer Memory Reclamation Engine with AddressSanitizer

Your goal is to implement a generic Hazard Pointer Memory Reclamation Engine in C11, compiled with AddressSanitizer (`-fsanitize=address`).

In `target.c`, you are given an engine structure with hazard pointer slots and a retired list per thread.
You must implement three lock-free functions:
- `hp_acquire(int thread_id, int slot, void *ptr)`: Sets a hazard pointer to protect an allocated object from being freed while reading.
- `hp_release(int thread_id, int slot)`: Clears the hazard pointer slot.
- `hp_retire(int thread_id, void *ptr)`: Retires a pointer for future reclamation. If the retired list grows beyond a threshold, it must trigger a scan and reclaim any pointer NOT currently protected by any active hazard pointer.
- `hp_reclaim_all(int thread_id)`: Forces reclamation of all retired pointers belonging to a thread upon completion.

## Requirements
1. **Lock-Free Reclamation**: Use C11 atomic operations (`<stdatomic.h>`) to read hazard pointer slots during reclamation scans.
2. **AddressSanitizer Safety**: This task is compiled with `-fsanitize=address`.
   - If your engine reclaims and frees a pointer while another thread still holds a hazard pointer to it, ASAN will trigger a **use-after-free** crash.
   - If your engine fails to reclaim retired pointers upon shutdown, ASAN will trigger a **memory leak** error.
3. **No Double-Frees**: A retired node can only be freed exactly once.

The stress test will spawn 16 concurrent threads allocating, sharing, protecting, and retiring 300,000 dynamic memory objects.

When you are done, compile the code using `gcc -O3 -Wall -Werror -pthread -fsanitize=address -o /out/hazard_bench target.c` and ensure it runs successfully without ASAN errors. If it prints "FLAG: Hazard Engine ASAN Success!", you have passed.
