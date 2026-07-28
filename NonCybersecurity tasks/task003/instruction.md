# Task 065: Single Point of Failure (SPOF) Analysis in Massive Directed Networks

You are given a text file `tests/network.txt` containing the topology of a massive directed computer network.

## Graph Specification
- The first line contains two integers $V$ and $E$, representing the number of nodes (routers) and directed edges (links).
- Nodes are numbered from $0$ to $V - 1$.
- The second line contains $2E$ integers representing the directed edges. Each pair $u, v$ indicates a one-way link from $u$ to $v$.
- The graph is massive: $V \approx 50,000$ and $E \approx 150,000$.

## The Challenge
A **Strong Bridge** is defined as a directed edge $e = (u, v)$ whose removal strictly increases the total number of Strongly Connected Components (SCCs) in the graph. 
In a real-world network, if a strong bridge fails, it irreversibly fragments a strongly connected routing zone, making two-way communication between certain segments impossible.

Your objective is to find the **exact number of strong bridges** in the given graph.

## Implementation Details
You must write a Python 3 script `solution.py` that implements the following class:
```python
class NetworkVulnerability:
    def count_strong_bridges(self, filepath: str) -> int:
        pass
```

- **Performance Constraint**: Due to the massive size of the graph, a naive algorithm (such as removing each edge and running Tarjan's algorithm $O(E(V+E))$) will catastrophically time out.
- You must derive and implement an incredibly efficient linear-time $O(V+E)$ algorithm (or near-linear time) to identify these critical strong bridges.
- Beware of Python's recursion limit! Standard recursive DFS implementations will hit `RecursionError`. You must either increase the limit using `sys.setrecursionlimit()` appropriately, or write an iterative DFS.
