# Task 079: Lattice-Based Zero-Knowledge Ring Polynomial Bound Verifier

You are a post-quantum cryptography engineer implementing a **Lattice-Based Zero-Knowledge Proof Verifier** over polynomial ring $R_q = \mathbb{Z}_q[X] / (X^N + 1)$ with $N=8, q=8380417$.

## Mathematical Foundation

In Dilithium/Kyber-like lattice ZK proofs:
1. Polynomials are vectors of length $N$ representing $P(X) = \sum_{i=0}^{N-1} c_i X^i \pmod q$.
2. **Ring Multiplication**: Multiplication of $A(X), B(X)$ modulo $X^N + 1$ over $\mathbb{Z}_q$:
   $$C(X) = A(X) \cdot B(X) \pmod{X^N + 1} \pmod q$$
3. **ZK Proof Response Relation**:
   $$z(X) = y(X) + c(X) \cdot s(X) \pmod q$$
   Where $y$ is masking polynomial, $c$ is challenge polynomial, $s$ is secret key polynomial.
4. **Infinity Norm Bound Check**:
   For the proof to be valid and leak zero information, every coefficient of $z(X)$ must satisfy:
   $$\|z\|_\infty = \max_{0 \le i < N} |z_i \pmod q| \le \beta$$
   Where $z_i \pmod q$ is mapped to symmetric range $\left[-\frac{q-1}{2}, \frac{q-1}{2}\right]$ and $\beta = 1000$.

## Input Schema (`tests/lattice_proof.json`)

```json
{
  "N": 8,
  "q": 8380417,
  "beta": 1000,
  "c": [1, -1, 0, 0, 1, 0, -1, 0],
  "s": [2, 3, -1, 0, 4, 1, 0, -2],
  "y": [10, 20, 30, 40, 50, 60, 70, 80]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `LatticeZKVerifier`:
```python
class LatticeZKVerifier:
    def verify_proof(self, filepath: str) -> dict:
        # filepath: path to lattice_proof.json
        # returns: dict {"bound_valid": bool, "z_coefficients": [int_0, ...], "norm_infinity": int_val}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/lattice_result.json`.

## Constraints
- **Python Standard Library Only** (`json`, `os`, `sys`).
- Symmetric modulo centering for norm: $v_{sym} = ((v + \lfloor q/2 \rfloor) \pmod q) - \lfloor q/2 \rfloor$.
