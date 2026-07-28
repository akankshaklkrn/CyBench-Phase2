# Task 067: Post-Quantum Module-LWE Decryption Engine

You are implementing a **Post-Quantum Cryptography (PQC)** decryption module based on the **Module Learning With Errors (Module-LWE)** problem (similar to CRYSTALS-Kyber / ML-KEM).

## Mathematical Specification

All polynomial operations are defined over the ring $R_q = \mathbb{Z}_q[X] / (X^n + 1)$, where:
- Degree $n = 256$
- Prime modulus $q = 3329$
- Modulus reduction polynomial: $X^{256} + 1 \equiv 0 \pmod q$

### Key & Ciphertext Components
1. **Secret Key vector $s$**: A vector of 2 polynomials $s = [s_0(X), s_1(X)]$, each with 256 integer coefficients in $\mathbb{Z}_q$.
2. **Ciphertext vector $c = (u, v)$**:
   - $u = [u_0(X), u_1(X)]$: A vector of 2 polynomials.
   - $v(X)$: A single polynomial.

### Decryption Formula
1. Compute noise-corrupted message polynomial $m_{noisy}(X)$:
   $$m_{noisy}(X) = v(X) - (s_0(X) \cdot u_0(X) + s_1(X) \cdot u_1(X)) \pmod{q, X^{256}+1}$$

2. **Polynomial Multiplication modulo $(X^{256}+1, q)$**:
   When multiplying two polynomials $A(X) \cdot B(X)$, any term $c_k X^k$ with exponent $k \ge 256$ is reduced via $X^{256} \equiv -1 \pmod q$:
   $$X^{256 + j} \equiv -X^j \pmod{X^{256}+1}$$

3. **Message Bit Decoding**:
   For each coefficient $m_{noisy}[i]$ ($0 \le i < 256$):
   - Compute distance to $\lceil q/2 \rceil = 1665$:
     - If $|m_{noisy}[i] - 1665| < 832$, decoded bit $b_i = 1$.
     - Otherwise, decoded bit $b_i = 0$.

4. Assemble the 256 decoded bits into **32 bytes** (little-endian per byte: bit 0 = LSB of byte 0).

## Input File Format

The file `tests/lwe_ciphertext.json` contains:
```json
{
  "n": 256,
  "q": 3329,
  "secret_key": {
    "s0": [c0, c1, ... c255],
    "s1": [c0, c1, ... c255]
  },
  "ciphertext": {
    "u0": [c0, c1, ... c255],
    "u1": [c0, c1, ... c255],
    "v": [c0, c1, ... c255]
  }
}
```

## Implementation

Write a Python 3 script `solution.py` with the class `ModuleLWEDecryptor`:
```python
class ModuleLWEDecryptor:
    def decrypt(self, filepath: str) -> str:
        # filepath: path to lwe_ciphertext.json
        # returns: decrypted plaintext ASCII string
        pass
```

When run directly (`python3 solution.py`), write the decrypted plaintext string to `/src/decrypted_pqc_msg.txt`.

## Rules & Constraints
- **Python Standard Library Only** (no `numpy`, `scipy`, or `sympy`).
- You must implement polynomial ring multiplication modulo $(X^{256}+1, 3329)$ correctly.
