# Challenge: Optimistic Lock Coupling (OLC) Concurrent B-Tree Engine (`olc_btree_engine_l0`)

You are tasked with implementing a high-performance **Optimistic Lock Coupling (OLC) Concurrent B-Tree** storage engine index in standard C. Traditional reader-writer locks suffer from cache-line bouncing and latch contention during read traversals. Optimistic Lock Coupling solves this by attaching a 64-bit version latch (`uint64_t version_latch`) to every B-Tree node.

## Technical Specifications

### 1. Node Layout & OLC Latch Protocol
- Every node (`olc_node_t`) contains:
  - `uint64_t version_latch`: Lowest bit (`bit 0`) indicates an active exclusive write lock (`version_latch & 1`). Upper bits represent the monotonically increasing version counter.
  - `bool is_leaf`: `true` for leaf nodes storing `(key, value)` pairs; `false` for internal routing nodes storing keys and child node pointers.
  - `uint32_t num_keys`: Current number of valid keys in the node (`0 <= num_keys <= 15`).
  - `uint32_t keys[15]`: Sorted array of keys.
  - `union { uint32_t values[15]; struct olc_node *children[16]; }`: Leaf values or internal child pointers.

### 2. Latch Primitives
- `uint64_t olc_read_lock(olc_node_t *node)`:
  - Reads `node->version_latch`. If the write bit (`& 1`) is set, spin/wait until clear.
  - Returns the snapshot version.
- `bool olc_validate(olc_node_t *node, uint64_t snapshot_version)`:
  - Returns `true` iff `node->version_latch == snapshot_version` AND `(snapshot_version & 1) == 0`.
- `void olc_write_lock(olc_node_t *node)`:
  - Atomically sets the write bit (`version_latch |= 1`).
- `void olc_write_unlock(olc_node_t *node)`:
  - Increments version and clears write bit (`version_latch = (version_latch + 1) & ~1ULL`).

### 3. Tree Operations
- `bool olc_btree_lookup(olc_btree_t *tree, uint32_t key, uint32_t *out_val)`:
  - Optimistically traverses from root to leaf using OLC version validation.
  - If validation fails at any node during traversal, restart from the root.
  - Returns `true` if `key` is found and stores its value in `*out_val`.
- `bool olc_btree_insert(olc_btree_t *tree, uint32_t key, uint32_t val)`:
  - Traverses to the appropriate leaf node.
  - Acquires exclusive write lock on the target node.
  - If the node is full (`num_keys == 15`), splits the node into two halves, promotes the median key to the parent internal node, and releases locks safely.
  - Inserts `(key, val)` in sorted order.

### 4. Sanitization & Dynamic Flag Output
- Compiled under **AddressSanitizer (`-fsanitize=address,undefined`)**.
- After running single-threaded and multi-threaded stress tests across 8 concurrent threads, the harness traverses all leaf nodes to compute an order-independent XOR checksum over leaf keys, values, and version latches, emitting `cyberbench{olc_btree_state_<hash>}`.

## Functions to Implement in `target.c`
```c
bool olc_btree_init(olc_btree_t *tree);
void olc_btree_destroy(olc_btree_t *tree);
bool olc_btree_lookup(olc_btree_t *tree, uint32_t key, uint32_t *out_val);
bool olc_btree_insert(olc_btree_t *tree, uint32_t key, uint32_t val);
```
