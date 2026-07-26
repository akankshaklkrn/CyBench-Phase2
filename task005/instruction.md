# Task 066: Hyper-Spatial Geofencing Database (4D Range Containment Queries)

You are a backend engineer building a high-performance geofencing engine for a satellite constellation management system. The system tracks objects across **four spatial dimensions**: `x`, `y`, `z`, and `t` (time).

A geofence is defined as a 4-dimensional axis-aligned bounding box (hyper-rectangle). Each geofence has an associated integer **weight**. Given a stream of 4D query points, you must determine, for each point, the **sum of the weights** of all geofences that contain that point.

## Input Format

You are given two files:

### `tests/hyper_rects.csv`
Each line defines one hyper-rectangle in the format:
```
x_min,x_max,y_min,y_max,z_min,z_max,t_min,t_max,weight
```
- All coordinate values are floating-point numbers in the range $[-1000.0, 1000.0]$.
- For every rectangle, it is guaranteed that `x_min < x_max`, `y_min < y_max`, `z_min < z_max`, `t_min < t_max`.
- Weights are arbitrary integers in the range $[-10000, 10000]$.
- There are exactly **$N = 50,000$** hyper-rectangles.

### `tests/queries.csv`
Each line defines one 4D query point in the format:
```
x,y,z,t
```
- All coordinate values are floating-point numbers.
- There are exactly **$Q = 10,000$** query points.

## Output Format

Your solution must produce a file `/src/results.txt` containing exactly $Q$ lines. The $i$-th line must contain a single integer: the sum of weights of all hyper-rectangles that **contain** the $i$-th query point.

A point $(x, y, z, t)$ is **contained** by hyper-rectangle $[x_{min}, x_{max}] \times [y_{min}, y_{max}] \times [z_{min}, z_{max}] \times [t_{min}, t_{max}]$ if and only if:

$$x_{min} \le x \le x_{max} \quad \land \quad y_{min} \le y \le y_{max} \quad \land \quad z_{min} \le z \le z_{max} \quad \land \quad t_{min} \le t \le t_{max}$$

## Implementation Requirements

1. You must write a Python 3 script `solution.py` that reads the two CSV files, computes the answers, and writes `results.txt`.
2. **You MUST NOT use any external spatial indexing libraries** such as `rtree`, `scipy.spatial`, `shapely`, `sklearn.neighbors`, or any other pre-built spatial data structure. You may only use the Python standard library and `numpy` (for array operations only, not spatial queries).
3. **Performance constraint**: Your solution must complete within **120 seconds** on the provided dataset. A naive $O(N \times Q)$ brute-force approach scanning all 50,000 rectangles for each of 10,000 queries will take approximately 500 million comparisons and **will time out**. You must implement an efficient spatial index (e.g., a KD-Tree, R-Tree, Bounding Volume Hierarchy, or interval tree) from scratch.
4. **Precision**: Use `<=` (less-than-or-equal) comparisons for containment checks. Floating-point comparisons must be exact (no epsilon tolerance).

## Difficulty Notes

- The hyper-rectangles are **heavily overlapping** in all four dimensions, making naive dimension-reduction strategies ineffective.
- Many query points are deliberately placed at the **exact boundaries** of hyper-rectangles to stress floating-point edge cases.
- The weight values include **negative numbers**, so you cannot use early termination heuristics based on monotonic accumulation.
- A correct but slow solution will time out. A fast but incorrect solution will produce wrong sums. You must achieve **both correctness and speed**.
