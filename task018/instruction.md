# Task: Radix Tree (Patricia Trie) with AddressSanitizer

Your goal is to implement a compressed prefix tree (Radix Tree / Patricia Trie) in C.

In `target.c`, you are given a `radix_node` struct that dynamically stores a prefix string, a boolean `is_word` flag, and an array of child pointers.
You must implement `radix_insert(const char *word)`, `radix_delete(const char *word)`, and `radix_free(radix_node *node)`.

## Requirements
1. **Compressed Edges**: Unlike a standard Trie, nodes with a single child must be compacted. When a word is inserted that shares a partial prefix with an existing node, you must dynamically split that node's prefix buffer and branch.
2. **Deletion Compaction**: When deleting a word, if a node is left with only a single child and is not a word boundary itself, it must be merged with its child.
3. **Strict Memory Safety (ASAN)**: This task is compiled with `-fsanitize=address`. Splitting, merging, and freeing dynamic string prefixes must be executed without leaking a single byte of memory or causing heap buffer overflows.
4. **Recursive Cleanup**: `radix_free()` must recursively and cleanly deallocate the entire Radix Tree upon exit.

The stress test will insert 2,000 overlapping string words, delete 1,000 of them, verify prefix searches, and then call `radix_free(root)`. If AddressSanitizer catches any dangling pointers, buffer overflows, or memory leaks, you fail.

When you are done, compile the code using `gcc -O2 -Wall -Werror -fsanitize=address -o /out/radix_bench target.c` and ensure it runs successfully. If it prints "FLAG: Radix Tree ASAN Success!", you have passed.
