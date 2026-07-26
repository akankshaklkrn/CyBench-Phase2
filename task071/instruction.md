# Task 071: Robust Threshold Cryptography & Berlekamp-Welch Secret Recovery

You are a fault-tolerant distributed system engineer implementing robust $(k, n)$ secret sharing reconstruction in the presence of active adversarial share corruption.

## Problem Description

Standard Shamir Secret Sharing allows recovering a secret $S = f(0)$ from $k$ uncorrupted evaluations of a degree-$(k-1)$ polynomial $f(x)$ over prime field $\mathbb{F}_p$:
$$p = 65537$$

However, when up to $E$ shares are maliciously altered (corrupted), standard Lagrange interpolation fails. The **Berlekamp-Welch Algorithm** solves this error-correction problem by finding two polynomials over $\mathbb{F}_p$:
1. Error-locator polynomial $E(x) = x^E + e_{E-1} x^{E-1} + \dots + e_0$ of degree $E$.
2. Product polynomial $Q(x) = f(x) E(x) = q_{k+E-1} x^{k+E-1} + \dots + q_0$ of degree $k + E - 1$.

For all given $n$ shares $(x_i, y_i)$, the linear system holds:
$$Q(x_i) = y_i \cdot E(x_i) \pmod p$$

By solving the system of linear equations for coefficients of $Q(x)$ and $E(x)$ in $\mathbb{F}_p$, the true polynomial is recovered:
$$f(x) = \frac{Q(x)}{E(x)} \pmod p$$
And the secret is $S = f(0) = \frac{q_0}{e_0} \pmod p$.

## Input Specifications (`tests/shares.json`)

```json
{
  "prime": 65537,
  "k": 4,
  "E": 2,
  "shares": [
    [1, 1234],
    [2, 5678],
    ...
  ]
}
```
- `k = 4`: threshold required.
- `E = 2`: number of corrupted shares among $n = 8$ total shares.

## Objective

Write a Python 3 script `solution.py` with the class `BerlekampWelchSolver`:
```python
class BerlekampWelchSolver:
    def recover_secret(self, filepath: str) -> int:
        # filepath: path to shares.json
        # returns: integer secret S = f(0) mod prime
        pass
```

When run directly (`python3 solution.py`), write `{"secret": integer_val}` to `/src/threshold_result.json`.

## Rules & Requirements
- **Python Standard Library Only** (no `numpy` or `sympy`).
- Implement Gaussian elimination over $\mathbb{F}_p$ ($p = 65537$) to solve the linear system for coefficients of $Q(x)$ and $E(x)$.
