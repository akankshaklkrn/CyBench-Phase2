#!/usr/bin/env bash
cat << 'EOF' > solution.py
import sys
from collections import defaultdict

# Increase recursion depth for deep graphs if we used recursive DFS
sys.setrecursionlimit(200000)

class NetworkVulnerability:
    def count_strong_bridges(self, filepath: str) -> int:
        with open(filepath, 'r') as f:
            lines = f.read().split()
            
        if not lines:
            return 0
            
        V = int(lines[0])
        E = int(lines[1])
        
        adj = [[] for _ in range(V)]
        idx = 2
        for _ in range(E):
            u = int(lines[idx])
            v = int(lines[idx+1])
            idx += 2
            adj[u].append(v)
            
        # 1. Find SCCs using iterative Tarjan's to avoid recursion limits on massive graphs
        ids = [-1] * V
        low = [-1] * V
        on_stack = [False] * V
        stack = []
        id_counter = 0
        scc_of = [-1] * V
        
        # We will use an explicit stack to simulate recursion
        # Stack stores: (u, neighbors_iterator, is_first_visit)
        for i in range(V):
            if ids[i] == -1:
                call_stack = [(i, 0)]
                while call_stack:
                    u, neighbor_idx = call_stack.pop()
                    
                    if neighbor_idx == 0:
                        ids[u] = low[u] = id_counter
                        id_counter += 1
                        stack.append(u)
                        on_stack[u] = True
                        
                    # Process neighbors
                    while neighbor_idx < len(adj[u]):
                        v = adj[u][neighbor_idx]
                        neighbor_idx += 1
                        
                        if ids[v] == -1:
                            # Pause current node, push it back, and recurse on v
                            call_stack.append((u, neighbor_idx))
                            call_stack.append((v, 0))
                            break
                        elif on_stack[v]:
                            low[u] = min(low[u], ids[v])
                            
                    else: # All neighbors processed
                        # If we are returning from a child, we need to update low[parent]
                        if call_stack:
                            parent, _ = call_stack[-1]
                            low[parent] = min(low[parent], low[u])
                            
                        # If u is a root node, pop the stack and generate an SCC
                        if low[u] == ids[u]:
                            while True:
                                w = stack.pop()
                                on_stack[w] = False
                                scc_of[w] = u  # Use root u as SCC id
                                if w == u:
                                    break
                                    
        # 2. Group nodes by SCC
        scc_nodes = defaultdict(list)
        for i in range(V):
            scc_nodes[scc_of[i]].append(i)
            
        strong_bridges = 0
        
        # 3. For each SCC, check internal edges
        for root, nodes_in_scc in scc_nodes.items():
            if len(nodes_in_scc) == 1:
                continue # No internal edges
                
            node_set = set(nodes_in_scc)
            
            # Find all internal edges
            internal_edges = []
            for u in nodes_in_scc:
                for v in adj[u]:
                    if v in node_set:
                        internal_edges.append((u, v))
                        
            # For each internal edge (u, v), check if there is an alternative path from u to v
            for u, v in internal_edges:
                # BFS from u to v, ignoring the direct edge (u, v)
                visited = set([u])
                q = [u]
                found = False
                
                while q:
                    curr = q.pop(0)
                    if curr == v:
                        found = True
                        break
                        
                    for nxt in adj[curr]:
                        if nxt in node_set:
                            # Ignore the direct edge we are testing
                            if curr == u and nxt == v:
                                continue
                            if nxt not in visited:
                                visited.add(nxt)
                                q.append(nxt)
                                
                if not found:
                    strong_bridges += 1
                    
        return strong_bridges
EOF
