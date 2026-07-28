# Task: AVL Tree Implementation

Your goal is to implement a strict AVL Tree in C.

In the `target.c` file, you will find the `avl_node` struct (which tracks height) and the global `root` pointer. 
You must implement two functions: `avl_insert` and `avl_delete`.

## Requirements
You MUST maintain the following mathematical invariants flawlessly:
1. **Binary Search Tree Property**: For every node, all values in the left subtree must be strictly less, and all values in the right subtree must be strictly greater.
2. **Strict Height-Balance Property**: For *every single node*, the height of its left subtree and right subtree can differ by at most 1 (`abs(height(left) - height(right)) <= 1`).
3. **Height Tracking**: You must correctly update and track the `height` attribute of nodes as the tree rotates.

The stress test will insert 1000 nodes, delete 500 nodes, and then recursively traverse the tree to verify that every single node satisfies the balance factor and BST properties. If you fail to perform the single or double (Left-Right/Right-Left) rotations correctly, the test will immediately fail.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/avltree_bench target.c` and ensure it runs successfully without crashing. If it prints "FLAG: AVL-Tree Success!", you have passed.
