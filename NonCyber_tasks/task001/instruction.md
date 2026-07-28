# Task 061: Lock-Free Stack ABA Problem

You are provided with a C++ lock-free stack implementation in `tests/template.cpp` based on a standard Treiber stack. However, the current implementation contains a fatal vulnerability: it is susceptible to the ABA problem because it immediately deletes popped nodes.

Your goal is to fix the ABA problem. 

## Requirements:
1. You must implement a strictly lock-free solution.
2. You CANNOT use `std::mutex`, `std::lock_guard`, `std::unique_lock`, `std::atomic_flag`, or any other form of blocking spinlocks.
3. You must ensure that nodes are safely reclaimed and the stack remains consistent under heavy thread contention.

Write your solution to `solution.cpp`. Do NOT modify `main.cpp`.
