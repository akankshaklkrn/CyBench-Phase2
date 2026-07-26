#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
"""
Oracle Solution for Task 066: 4D Hyper-Spatial Geofencing.
Uses a custom 4D Bounding Volume Hierarchy (BVH) for efficient containment queries.
"""
import sys
import os

class BVHNode:
    __slots__ = ['bbox', 'left', 'right', 'rects']
    def __init__(self):
        self.bbox = None
        self.left = None
        self.right = None
        self.rects = None

def compute_bbox(rects):
    x_min = min(r[0] for r in rects)
    x_max = max(r[1] for r in rects)
    y_min = min(r[2] for r in rects)
    y_max = max(r[3] for r in rects)
    z_min = min(r[4] for r in rects)
    z_max = max(r[5] for r in rects)
    t_min = min(r[6] for r in rects)
    t_max = max(r[7] for r in rects)
    return (x_min, x_max, y_min, y_max, z_min, z_max, t_min, t_max)

def center(rect, dim):
    return (rect[dim*2] + rect[dim*2+1]) / 2.0

def build_bvh(rects, depth=0, max_leaf=32):
    node = BVHNode()
    node.bbox = compute_bbox(rects)

    if len(rects) <= max_leaf:
        node.rects = rects
        return node

    # Pick split axis: widest spread
    best_axis = 0
    best_spread = 0.0
    for a in range(4):
        spread = node.bbox[a*2+1] - node.bbox[a*2]
        if spread > best_spread:
            best_spread = spread
            best_axis = a

    rects_sorted = sorted(rects, key=lambda r: center(r, best_axis))
    mid = len(rects_sorted) // 2

    left_rects = rects_sorted[:mid]
    right_rects = rects_sorted[mid:]

    if not left_rects or not right_rects:
        node.rects = rects
        return node

    node.left = build_bvh(left_rects, depth + 1, max_leaf)
    node.right = build_bvh(right_rects, depth + 1, max_leaf)
    return node

def point_in_bbox(px, py, pz, pt, bbox):
    return (bbox[0] <= px <= bbox[1] and
            bbox[2] <= py <= bbox[3] and
            bbox[4] <= pz <= bbox[5] and
            bbox[6] <= pt <= bbox[7])

def query_bvh(node, px, py, pz, pt):
    if not point_in_bbox(px, py, pz, pt, node.bbox):
        return 0

    if node.rects is not None:
        total = 0
        for r in node.rects:
            if r[0] <= px <= r[1] and r[2] <= py <= r[3] and r[4] <= pz <= r[5] and r[6] <= pt <= r[7]:
                total += r[8]
        return total

    return query_bvh(node.left, px, py, pz, pt) + query_bvh(node.right, px, py, pz, pt)

def main():
    rects_path = "/tests/hyper_rects.csv"
    queries_path = "/tests/queries.csv"
    if not os.path.exists(rects_path):
        rects_path = "/Users/jatinjena/Downloads/tasknew/task066/tests/hyper_rects.csv"
        queries_path = "/Users/jatinjena/Downloads/tasknew/task066/tests/queries.csv"

    rects = []
    with open(rects_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 9:
                vals = [float(x) for x in parts[:8]]
                vals.append(int(float(parts[8])))
                rects.append(tuple(vals))

    sys.setrecursionlimit(200000)
    root = build_bvh(rects, max_leaf=32)

    results = []
    with open(queries_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) == 4:
                px, py, pz, pt = float(parts[0]), float(parts[1]), float(parts[2]), float(parts[3])
                results.append(query_bvh(root, px, py, pz, pt))

    os.makedirs("/src", exist_ok=True)
    with open("/src/results.txt", "w") as f:
        for r in results:
            f.write(f"{r}\n")

if __name__ == "__main__":
    main()
PYEOF
cd /src && python3 solution.py
