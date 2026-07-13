# Task: B+ Tree Implementation

Your goal is to implement a B+ Tree in C.

In the `target.c` file, you will find the `bplus_node` struct and the global `root` pointer. 
You must implement two functions: `bplus_insert` and `bplus_delete`.

## Requirements
Unlike a standard B-Tree, a **B+ Tree** has strict structural requirements:
1. **Data at Leaves**: All data values must be stored strictly at the leaf level. Internal nodes only store keys for routing.
2. **Linked Leaves**: Every leaf node must maintain a `next` pointer to the adjacent leaf node, forming a linked list for fast range queries.
3. **Borrowing and Merging**: During deletion, if a node underflows, you must correctly borrow from a sibling or merge nodes while simultaneously keeping the leaf-level linked list completely intact.

The stress test will insert 10,000 nodes, delete 5,000 of them, and then verify that the B+ Tree properties hold, and critically, that traversing the leaf-level linked list yields a perfectly sorted array of the remaining 5,000 elements.

When you are done, compile the code using `gcc -O2 -Wall -Werror -o /out/bplus_bench target.c` and ensure it runs successfully without crashing. If it prints "FLAG: B+ Tree Success!", you have passed.
