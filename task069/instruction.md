# Task 069: Fully Homomorphic Encryption (FHE) CKKS Tensor Multiplication Engine

You are a privacy-preserving cryptography engineer implementing a **Fully Homomorphic Encryption (FHE)** tensor multiplication engine based on the **CKKS (Cheon-Kim-Kim-Song)** scheme.

## Background & CKKS Arithmetic

In the CKKS homomorphic scheme over fixed-point real vectors:
1. **Ciphertexts** $c_A = (c_0^{(A)}, c_1^{(A)})$ and $c_B = (c_0^{(B)}, c_1^{(B)})$ encrypt vectors $x, y \in \mathbb{R}^N$ with scaling factor $\Delta = 2^{40}$ and coefficient modulus $Q = 1152921504606846976$ ($2^{60}$).
2. **Homomorphic Multiplication** produces a 3-element ciphertext tuple:
   $$(d_0, d_1, d_2) = (c_0^{(A)} \cdot c_0^{(B)}, \quad c_0^{(A)} \cdot c_1^{(B)} + c_1^{(A)} \cdot c_0^{(B)}, \quad c_1^{(A)} \cdot c_1^{(B)}) \pmod{Q, X^N + 1}$$
3. **Relinearization**: Given evaluation key $evk = (evk_0, evk_1)$, reduce the 3-element tuple back to a standard 2-element ciphertext $(c_0', c_1')$:
   $$c_0' = d_0 + \lfloor (d_2 \cdot evk_0) / \Delta \rceil \pmod{Q, X^N + 1}$$
   $$c_1' = d_1 + \lfloor (d_2 \cdot evk_1) / \Delta \rceil \pmod{Q, X^N + 1}$$
4. **Rescaling / Division by $\Delta$**: Reduce the quadratic scale factor $\Delta^2$ down to $\Delta$:
   $$c_0 = \lfloor c_0' / \Delta \rceil \pmod Q$$
   $$c_1 = \lfloor c_1' / \Delta \rceil \pmod Q$$

## Input Data Specification (`tests/fhe_data.json`)

```json
{
  "N": 64,
  "Q": 1152921504606846976,
  "scale": 1099511627776,
  "cA": {"c0": [...], "c1": [...]},
  "cB": {"c0": [...], "c1": [...]},
  "evk": {"evk0": [...], "evk1": [...]}
}
```

## Objective

Write a Python 3 script `solution.py` with the class `FHECKKSMultiplier`:
```python
class FHECKKSMultiplier:
    def multiply_and_rescale(self, filepath: str) -> dict:
        # filepath: path to fhe_data.json
        # returns: dict {"c0": [int, ...], "c1": [int, ...]} containing output ciphertext polynomials
        pass
```

When run directly (`python3 solution.py`), write the resulting `{"c0": [...], "c1": [...]}` dictionary to `/src/fhe_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (no `numpy`, `scipy`, `openfhe`, or `seal`).
- Polynomial multiplication must perform polynomial modular reduction modulo $X^N + 1 \equiv 0$.
