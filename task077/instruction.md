# Task 077: Dynamic RSA Cryptographic Accumulator Verifier

You are a decentralized storage security engineer verifying **Dynamic RSA Cryptographic Accumulator** membership and non-membership proofs.

## Mathematical Specification

Given an RSA composite modulus $N = p \cdot q$ and base generator $g = 65537$:
An accumulator value $V$ accumulates a set of elements $S = \{y_1, y_2, \dots, y_k\}$ mapped to prime representatives $p_i = \text{PrimeMap}(y_i)$:
$$V = g^{\prod_{i=1}^k p_i} \pmod N$$

### 1. Membership Proof Verification
To prove an element $y \in S$ with prime representative $p_y$:
- The prover provides witness $W_y = g^{\prod_{i \neq y} p_i} \pmod N$.
- The verifier verifies:
  $$W_y^{p_y} \equiv V \pmod N$$

### 2. Non-Membership Proof Verification
To prove an element $z \notin S$ with prime representative $p_z$:
- Since $p_z$ is prime and co-prime to $\prod_{i=1}^k p_i$, Extended Euclidean Algorithm yields Bezout identity coefficients $(d, d')$ such that:
  $$d \cdot \left(\prod_{i=1}^k p_i\right) + d' \cdot p_z = 1$$
- The prover provides non-membership witness tuple $(W_{non}, d, d')$ where $W_{non} = g^d \pmod N$.
- The verifier verifies the identity:
  $$(V^d \cdot W_{non}^{p_z}) \equiv g \pmod N$$

## Input Schema (`tests/accumulator_proof.json`)

```json
{
  "N": "...",
  "g": 65537,
  "V": "...",
  "membership_test": {
    "y": "item_42",
    "py": 104729,
    "W": "..."
  },
  "non_membership_test": {
    "z": "item_99",
    "pz": 104743,
    "d": -12345,
    "W_non": "..."
  }
}
```

## Objective

Write a Python 3 script `solution.py` with the class `RSAAccumulatorVerifier`:
```python
class RSAAccumulatorVerifier:
    def verify_proofs(self, filepath: str) -> dict:
        # filepath: path to accumulator_proof.json
        # returns: dict {"membership_valid": bool, "non_membership_valid": bool}
        pass
```

When run directly (`python3 solution.py`), write the output dictionary to `/src/accumulator_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`json`, `math`, `os`, `sys`).
- Modular exponentiation must support negative powers ($x^{-d} \equiv (x^{-1})^d \pmod N$).
