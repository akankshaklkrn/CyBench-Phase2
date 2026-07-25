import random
from collections import defaultdict

class NetworkVulnerability:
    def count_2_edge_cutsets(self, filepath: str) -> int:
        with open(filepath, 'r') as f:
            lines = f.read().split()
            
        if not lines:
            return 0
            
        V = int(lines[0])
        E = int(lines[1])
        
        adj = [[] for _ in range(V)]
        edges = []
        idx = 2
        for i in range(E):
            u = int(lines[idx])
            v = int(lines[idx+1])
            idx += 2
            adj[u].append((v, i))
            adj[v].append((u, i))
            edges.append((u, v))
            
        # BFS to find Spanning Tree
        parent_edge = [-1] * V
        parent_node = [-1] * V
        order = []
        visited = [False] * V
        
        visited[0] = True
        queue = [0]
        tree_edges = set()
        
        while queue:
            u = queue.pop(0)
            order.append(u)
            for v, e_idx in adj[u]:
                if not visited[v]:
                    visited[v] = True
                    parent_edge[v] = e_idx
                    parent_node[v] = u
                    tree_edges.add(e_idx)
                    queue.append(v)
                    
        # Assign random weights to back-edges
        edge_hash = [0] * E
        node_xor = [0] * V
        
        for i in range(E):
            if i not in tree_edges:
                w = random.getrandbits(64)
                edge_hash[i] = w
                u, v = edges[i]
                node_xor[u] ^= w
                node_xor[v] ^= w
                
        # Bottom-up DP to compute tree-edge hashes
        for u in reversed(order):
            p = parent_node[u]
            if p != -1:
                e_idx = parent_edge[u]
                edge_hash[e_idx] = node_xor[u]
                node_xor[p] ^= node_xor[u]
                
        # Count frequencies
        freq = defaultdict(int)
        for i in range(E):
            h = edge_hash[i]
            if h != 0: # h == 0 means bridge (1-edge cut)
                freq[h] += 1
                
        # Calculate pairs
        total_pairs = 0
        for h, count in freq.items():
            total_pairs += (count * (count - 1)) // 2
            
        return total_pairs
