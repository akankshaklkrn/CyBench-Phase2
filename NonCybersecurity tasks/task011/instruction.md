# Task: Red-Black Tree Implementation

Your goal is to implement a strict Red-Black Tree in C.

In the `target.c` file, you will find the `rb_node` struct and the global `root` pointer. 
You must implement two functions: `rb_insert` and `rb_delete`.

## Requirements
You MUST maintain the following mathematical invariants flawlessly:
1. Every node is either RED or BLACK.
2. The root must always be BLACK.
3. No two adjacent nodes can be RED (a red node cannot have a red parent or red child).
4. Every path from a node to any of its descendant NULL pointers must contain the same number of BLACK nodes.

The stress test will insert 1000 nodes, delete 500 nodes, and then recursively traverse the tree to verify that every single mathematical invariant holds true. If you fail to rotate or recolor correctly, the test will immediately fail.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/rbtree_bench target.c` and ensure it runs successfully without crashing. If it prints "FLAG: RB-Tree Success!", you have passed.
