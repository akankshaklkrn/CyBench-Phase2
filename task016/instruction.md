# Task: Splay Tree Implementation

Your goal is to implement a Splay Tree (a self-adjusting Binary Search Tree) in C.

In the `target.c` file, you will find the `splay_node` struct and the global `root` pointer. 
You must implement three functions: `splay(int key)`, `splay_insert(int key)`, and `splay_delete(int key)`.

## Requirements
1. **The Splay Operation**: Every time a node is inserted, searched, or accessed, you must perform tree rotations to bring that node directly to the root of the tree.
2. **Rotation Cases**: You must implement all standard splay step rotations:
   - **Zig**: Single rotation when the parent is the root.
   - **Zig-Zig**: Double rotation when the node and parent are both left or both right children.
   - **Zig-Zag**: Double rotation when the node is a left child of a right parent (or vice versa).
3. **BST Invariant**: The tree must remain a valid Binary Search Tree at all times.

The stress test will perform 10,000 random insertions and accesses, and will check after *every single operation* that the recently touched node is now sitting at `root`, and that the tree is still a valid Binary Search Tree.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/splay_bench target.c` and ensure it runs successfully without crashing. If it prints "FLAG: Splay Tree Success!", you have passed.
