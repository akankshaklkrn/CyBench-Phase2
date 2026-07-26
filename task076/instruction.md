# Task 076: Bulletproofs Inner-Product Argument Verifier

You are a zero-knowledge proof cryptography engineer building a **Bulletproofs Inner-Product Argument Verifier** over finite field $\mathbb{F}_p$ ($p = 21888242871839275222246405745257275088548364400416034343698204186575808495617$, BN254).

## Inner Product Reduction Algorithm

Bulletproofs use a recursive $O(\log N)$ reduction to prove that $\langle a, b \rangle = c$ for secret vectors $a, b \in \mathbb{F}_p^N$ ($N = 2^k$):

### Interactive Reduction Step ($k$ rounds):
For each round $j = 0 \dots k-1$:
1. Split vectors in half: $a = (a_{lo}, a_{hi})$, $b = (b_{lo}, b_{hi})$.
2. Compute cross-term inner products:
   $$L_j = \langle a_{lo}, b_{hi} \rangle \pmod p$$
   $$R_j = \langle a_{hi}, b_{lo} \rangle \pmod p$$
3. Generate Fiat-Shamir challenge scalar $x_j$:
   $$x_j = \text{int}(\text{SHA256}(\text{str}(L_j) \parallel \text{str}(R_j)), 16) \pmod p$$
4. Fold vectors:
   $$a' = a_{lo} \cdot x_j + a_{hi} \cdot x_j^{-1} \pmod p$$
   $$b' = b_{lo} \cdot x_j^{-1} + b_{hi} \cdot x_j \pmod p$$
5. Final scalar check at base case $N=1$:
   $$c_{final} = a_{final} \cdot b_{final} \pmod p$$

## Input Schema (`tests/bulletproof_data.json`)

```json
{
  "prime": "21888242871839275222246405745257275088548364400416034343698204186575808495617",
  "N": 8,
  "a": [1, 2, 3, 4, 5, 6, 7, 8],
  "b": [10, 20, 30, 40, 50, 60, 70, 80],
  "proof": {
    "L": ["val_0", "val_1", ...],
    "R": ["val_0", "val_1", ...]
  }
}
```

## Objective

Write a Python 3 script `solution.py` with the class `BulletproofVerifier`:
```python
class BulletproofVerifier:
    def verify_inner_product(self, filepath: str) -> dict:
        # filepath: path to bulletproof_data.json
        # returns: dict {"valid": bool, "c_final": int_val}
        pass
```

When run directly (`python3 solution.py`), write the output dictionary to `/src/bulletproof_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `os`, `sys`).
- Modular inverse calculations must use Fermat's Little Theorem ($x^{-1} \equiv x^{p-2} \pmod p$).
