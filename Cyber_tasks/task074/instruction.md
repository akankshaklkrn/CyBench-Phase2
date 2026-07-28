# Task 074: Differential Privacy Aggregator & Budget Verifier

You are a Privacy-Preserving Data Engineer building a **Distributed Differential Privacy (DP) Aggregator** that validates privacy loss budgets $\epsilon$ and computes optimal Laplace noise addition.

## Problem Description

$N$ edge nodes submit noisy numerical query responses to a central privacy server. Each node $i$ applies a local Laplace noise mechanism:
$$\text{Noise}_i \sim \text{Laplace}\left(0, \frac{\Delta f}{\epsilon_i}\right)$$
Where $\Delta f$ is the global query sensitivity (maximum difference a single individual record can make).

### Privacy Loss Budget & Bounded Aggregation
1. **Cumulative Privacy Budget Verification**:
   - Total privacy budget consumed across queries: $\epsilon_{total} = \sum_{i=1}^N \epsilon_i$.
   - If $\epsilon_{total} > \epsilon_{max}$, the privacy budget is **exhausted**, and the mechanism must reject further queries to prevent identity re-identification.
2. **Aggregated Mean Estimation**:
   - Given node responses $y_i = x_i + \text{Noise}_i$, compute the weighted inverse-variance estimate of the true average $\bar{x}$:
     $$\hat{x} = \frac{\sum_{i=1}^N \epsilon_i^2 \cdot y_i}{\sum_{i=1}^N \epsilon_i^2}$$
3. **95% Confidence Interval Half-Width**:
   $$\text{CI}_{95} = 1.96 \cdot \sqrt{\frac{2 \cdot (\Delta f)^2}{\sum_{i=1}^N \epsilon_i^2}}$$

## Input Format (`tests/dp_queries.json`)

```json
{
  "sensitivity": 1.0,
  "max_epsilon_budget": 5.0,
  "queries": [
    {"node_id": "node_1", "epsilon": 0.5, "response": 42.8},
    {"node_id": "node_2", "epsilon": 0.5, "response": 41.5},
    ...
  ]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `DPAggregator`:
```python
class DPAggregator:
    def process_dp_queries(self, filepath: str) -> dict:
        # filepath: path to dp_queries.json
        # returns: dict {"budget_exceeded": bool, "estimated_mean": float, "ci_95": float} rounded to 4 decimal places
        pass
```

When run directly (`python3 solution.py`), write the output dictionary to `/src/dp_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`math`, `json`, `os`, `sys`).
- All float values in `estimated_mean` and `ci_95` must be rounded to **4 decimal places**.
