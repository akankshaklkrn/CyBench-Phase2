# Task 063: Authenticated Path ORAM with Furthest-Distance Eviction Priority

You are tasked with implementing the client logic for a secure, authenticated **Path Oblivious RAM (Path ORAM)** protocol. Standard Path ORAM implementations suffer from high stash usage and lack cryptographic integrity verification against a malicious storage server.

Your objective is to write a Python 3 script `solution.py` containing a class `AuthenticatedOramClient` (or `OramClient`) that simulates client operations over an untrusted binary storage tree while maintaining strict eviction ordering and SHA-256 authentication tags.

## Tree Architecture & Authentication Tags

- **Tree Dimensions**: The tree has depth $D=3$ (8 leaves, numbered $0 \dots 7$, corresponding to node IDs $8 \dots 15$). Total nodes: $15$ (numbered $1 \dots 15$, root is node $1$). Bucket capacity $Z=4$.
- **Node Data Structure**: Each node in `self.tree` is stored as a dictionary:
  ```python
  {
      "version": int, # Starts at 0 upon initialization
      "blocks": list, # List of exactly Z tuples: (block_id, data). Dummy block is (-1, 0)
      "hash": str     # Hexadecimal SHA-256 digest
  }
  ```
- **Hash Computation Rule**: 
  To securely authenticate a node, its SHA-256 tag MUST be calculated precisely as:
  ```python
  import hashlib
  # blocks MUST be sorted chronologically by block_id before hashing to ensure canonical representation!
  sorted_blocks = sorted(blocks, key=lambda x: (x[0], str(x[1])))
  raw_string = f"{node_id}:{version}:{sorted_blocks}"
  hash_tag = hashlib.sha256(raw_string.encode()).hexdigest()
  ```
- Upon initialization, all nodes $1 \dots 15$ are initialized with `version = 0`, `blocks = [(-1, 0)] * Z`, and their valid computed `hash_tag`.

## Access & Integrity Verification Workflow

When an operation `access(op: str, block_id: int, data=None)` is called:
1. **Lookup & Remap**: Look up the current mapped leaf $x = \text{pos\_map}[block\_id]$ and immediately remap $\text{pos\_map}[block\_id]$ to a new random leaf obtained by calling `self.leaf_rng()`.
2. **Path Integrity Verification (CRITICAL SECURITY STEP)**:
   Before reading blocks into `self.stash`, iterate through all nodes from root to leaf $x$.
   Recompute the expected SHA-256 tag for each node. If any node's `hash` does not match the computed tag, raise an `Exception("Integrity Violation")`.
3. **Read Path into Stash**: Move all real blocks ($block\_id \ne -1$) from the path nodes into `self.stash`, and reset path nodes to empty (dummies) temporarily.
4. **Perform Access**: If `op == 'read'`, return the data for `block_id` (or `0` if it was never written). If `op == 'write'`, update/add `(block_id, data)` in `self.stash`.
5. **Furthest-Distance Priority Eviction (CRITICAL ALGORITHMIC STEP)**:
   Evict blocks from the stash back onto the path from leaf $x$ up to the root (in bottom-up reversed order: leaf $\to$ root).
   For a node $u$ at depth $d$:
   - Identify all candidate blocks in `self.stash` whose current mapped leaf path includes node $u$.
   - If more than $Z$ candidates exist, **you MUST NOT pick arbitrarily**. You must select up to $Z$ candidates sorted by:
     1. **Largest target leaf index** (`pos_map[b_id]`).
     2. If target leaves are equal, tie-break by **smallest block_id**.
   - Remove chosen blocks from `self.stash`, pad the bucket to $Z$ with dummies `(-1, 0)`.
   - **Increment version**: Set `node["version"] += 1` (compared to its version prior to access), store the new blocks, and compute & update its new SHA-256 `hash`.

## Your Goal
Implement `solution.py` with:
```python
class OramClient:
    def __init__(self, D: int, Z: int, leaf_rng):
        pass

    def access(self, op: str, block_id: int, data=None):
        pass

    def get_server_tree(self) -> dict:
        return self.tree
```
The grader will test your implementation against rigorous deterministic access sequences and verify both cryptographic tags and furthest-distance eviction states!
