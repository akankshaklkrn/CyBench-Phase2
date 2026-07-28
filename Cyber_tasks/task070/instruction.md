# Task 070: Verifiable Delay Function (VDF) Wesolowski Proof Verifier

You are a cryptographic security protocol developer verifying a **Verifiable Delay Function (VDF)** evaluation using **Wesolowski's proof system** over an RSA integer group $\mathbb{Z}_N^*$.

## Background

A Verifiable Delay Function requires a prover to perform $T = 2^{16}$ sequential squaring operations:
$$y = x^{2^T} \pmod N$$
Computing $y$ takes significant sequential time, but verifying the result using Wesolowski's short proof $\pi$ takes only logarithmic time $O(\log T)$.

### Verification Protocol steps:
1. Parse the RSA modulus $N$, input element $x$, delay parameter $T$, claimed output $y$, and proof value $\pi$.
2. Compute the **Fiat-Shamir challenge prime $q$**:
   - Compute hash $h = \text{SHA256}(N \parallel x \parallel y \parallel \pi \parallel T)$ formatted as lowercase hex string.
   - Convert $h$ into an integer $val = \text{int}(h, 16)$.
   - Find the **next prime number $\ge val$** (deterministic primality testing via Miller-Rabin or trial division).
3. Compute the division remainder $r$:
   $$r = 2^T \pmod q$$
4. Compute $y_{check}$:
   $$y_{check} = (\pi^q \cdot x^r) \pmod N$$
5. Verify whether $y_{check} \equiv y \pmod N$.

## Input Format (`tests/vdf_proof.json`)

```json
{
  "N": "...",
  "x": "...",
  "T": 65536,
  "y": "...",
  "pi": "..."
}
```

## Objective

Write a Python 3 script `solution.py` with the class `VDFVerifier`:
```python
class VDFVerifier:
    def verify(self, filepath: str) -> bool:
        # filepath: path to vdf_proof.json
        # returns: True if valid proof, False otherwise
        pass
```

When run directly (`python3 solution.py`), write `{"valid": true}` or `{"valid": false}` to `/src/vdf_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `math`, `os`, `sys`).
- Implement Fiat-Shamir challenge prime search deterministically.
