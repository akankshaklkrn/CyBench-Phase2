# Task: Treap Implementation (BST + Heap Dual Invariants)

Your goal is to implement a Treap (Randomized Cartesian Tree) in C.

In `target.c`, you will find the `treap_node` struct which contains both an integer `key` and an integer `priority`, as well as the global `root` pointer.
You must implement `treap_insert(int key, int priority)` and `treap_delete(int key)`.

## Requirements
You MUST maintain TWO simultaneous mathematical invariants flawlessly at all times:
1. **Binary Search Tree Property**: With respect to node `key`s, all nodes in the left subtree must have strictly smaller keys, and all nodes in the right subtree must have strictly larger keys.
2. **Max-Heap Property**: With respect to node `priority`s, every parent node must have a `priority` strictly greater than or equal to both of its children.
3. **Rotations**: When inserting, you must insert as a leaf (satisfying BST) and then perform Left/Right tree rotations upwards until the Heap property is satisfied. When deleting, you must rotate the target node downwards with its highest-priority child until it is a leaf, then remove it.

The stress test will insert 5,000 nodes with randomized priorities, delete 2,500 nodes, and then recursively traverse the entire tree to verify that **both invariants** hold true for every single node. If either invariant is broken, you fail.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/treap_bench target.c` and ensure it runs successfully. If it prints "FLAG: Treap Success!", you have passed.
