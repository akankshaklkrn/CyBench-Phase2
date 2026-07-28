#!/usr/bin/env bash
cat << 'EOF' > solution.py
import hashlib

class OramClient:
    def __init__(self, D, Z, leaf_rng):
        self.D = D
        self.Z = Z
        self.leaf_rng = leaf_rng
        self.N = 1 << D
        self.pos_map = {}
        for i in range(self.N):
            self.pos_map[i] = self.leaf_rng()

        self.tree = {}
        num_nodes = (1 << (D + 1)) - 1
        for i in range(1, num_nodes + 1):
            blocks = [(-1, 0) for _ in range(Z)]
            tag = self._compute_hash(i, 0, blocks)
            self.tree[i] = {
                "version": 0,
                "blocks": blocks,
                "hash": tag
            }
        self.stash = {}

    def _compute_hash(self, node_id, version, blocks):
        sorted_blocks = sorted(blocks, key=lambda x: (x[0], str(x[1])))
        raw_string = f"{node_id}:{version}:{sorted_blocks}"
        return hashlib.sha256(raw_string.encode()).hexdigest()

    def get_path_nodes(self, leaf):
        nodes = []
        curr = leaf
        while curr >= 1:
            nodes.append(curr)
            curr //= 2
        return nodes[::-1]

    def access(self, op, block_id, data=None):
        x = self.pos_map[block_id]
        new_x = self.leaf_rng()
        self.pos_map[block_id] = new_x
        path_nodes = self.get_path_nodes(x)

        # 1. Verify integrity of path nodes
        for node_id in path_nodes:
            node = self.tree[node_id]
            expected_tag = self._compute_hash(node_id, node["version"], node["blocks"])
            if node["hash"] != expected_tag:
                raise Exception(f"Integrity Violation on node {node_id}")

        # 2. Read path into stash
        for node_id in path_nodes:
            node = self.tree[node_id]
            for b_id, b_data in node["blocks"]:
                if b_id != -1:
                    self.stash[b_id] = b_data
            # Temporarily empty blocks
            node["blocks"] = [(-1, 0) for _ in range(self.Z)]

        # 3. Perform operation
        ret_data = None
        if op == 'read':
            ret_data = self.stash.get(block_id, 0)
        elif op == 'write':
            self.stash[block_id] = data

        # 4. Furthest-Distance Priority Eviction (bottom-up: leaf to root)
        for node_id in reversed(path_nodes):
            candidates = []
            for b_id, b_data in self.stash.items():
                target_leaf = self.pos_map[b_id]
                target_path = self.get_path_nodes(target_leaf)
                if node_id in target_path:
                    candidates.append((b_id, b_data, target_leaf))

            # Sort by: 1. Largest target leaf index (descending), 2. Smallest block_id (ascending)
            candidates.sort(key=lambda item: (-item[2], item[0]))
            
            selected = candidates[:self.Z]
            bucket_blocks = []
            for b_id, b_data, _ in selected:
                bucket_blocks.append((b_id, b_data))
                del self.stash[b_id]

            while len(bucket_blocks) < self.Z:
                bucket_blocks.append((-1, 0))

            node = self.tree[node_id]
            new_version = node["version"] + 1
            new_tag = self._compute_hash(node_id, new_version, bucket_blocks)

            self.tree[node_id] = {
                "version": new_version,
                "blocks": bucket_blocks,
                "hash": new_tag
            }

        return ret_data

    def get_server_tree(self):
        return self.tree
EOF
