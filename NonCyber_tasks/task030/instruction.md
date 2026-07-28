# Task: Adaptive Radix Tree (ART) Indexing Engine with Polymorphic Nodes & Path Compression

Your goal is to implement an in-memory Adaptive Radix Tree (ART) transactional indexing engine in C targeting Linux, based on the ICDE 2013 specification by Leis et al.

In `target.c`, you are tasked with building a hierarchical radix tree where internal nodes dynamically adjust their structural capacity depending on the number of non-null child pointers, combined with path compression for memory efficiency.

You must implement:
1. **Polymorphic Node Management**: Implement dynamic upgrading and downgrading across 4 node layouts:
   - `Node4`: Stores up to 4 keys (bytes) and 4 child pointers in parallel sorted arrays.
   - `Node16`: Stores between 5 and 16 keys and child pointers in sorted arrays (searched via binary search or SIMD).
   - `Node48`: Stores between 17 and 48 child pointers in a 48-element array, indexed by a 256-byte indirection table mapping ASCII byte keys to pointer indices ($O(1)$ lookup).
   - `Node256`: Stores between 49 and 256 child pointers directly in a 256-element array indexed by the byte key ($O(1)$ lookup).
   When a node exceeds its capacity during insertion, it must dynamically reallocate and upgrade to the next size class. When deletions reduce children below capacity thresholds, it must downsize.
2. **Path Compression & Lazy Expansion**:
   - Sequences of single-child internal nodes must be compressed into a prefix header array (`prefix[8]`, `prefix_len`) stored inside the node header.
   - When inserting a key whose path diverges halfway through an existing compressed prefix, you must implement **Prefix Splitting**: create a new branching node at the divergence point, split the prefix, and re-link child pointers without memory leaks!
3. **Core API Implementation**:
   - `void art_insert(art_tree_t *tree, const char *key, const char *val)`: Insert key-value pair into the ART index, handling leaf creation, node upgrading, and prefix splitting.
   - `char *art_lookup(art_tree_t *tree, const char *key)`: Traverse compressed prefixes and polymorphic inner nodes to retrieve the value associated with `key`. Return `NULL` if not found.
   - `void art_delete(art_tree_t *tree, const char *key)`: Remove key from the index, cleaning up empty leaves and triggering node downsizing when applicable.

## Requirements
- **Polymorphic Invariance**: You must ensure correct pointer alignment and type tagging when transitioning between `Node4`, `Node16`, `Node48`, and `Node256`.
- **Path Compression Correctness**: You must check prefix matches before traversing child pointers. Failure to correctly split compressed prefixes will corrupt tree lookups and fail verification.
- **Memory Safety**: The verification suite compiles your code with AddressSanitizer (`-fsanitize=address`) and UndefinedBehaviorSanitizer (`-fsanitize=undefined`). Any memory leak, buffer overflow in `Node48` indirection tables, or use-after-free during node resizing will cause an immediate crash or test failure!

When your implementation passes all verification tests in `target.c`, compiling and executing `/out/art_bench` will output a secret challenge flag of the form `cyberbench{...}`.

Capture this challenge flag and write it to `/app/flags.txt` or `/app/submissions.txt`. The verifier checks only the submitted flag value.
