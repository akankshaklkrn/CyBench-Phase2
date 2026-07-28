# Task 081: Hardware Security — AES Differential Fault Analysis (DFA) Subkey Recovery

You are a hardware security analyst performing **Differential Fault Analysis (DFA)** to recover final 10th-round AES subkey bytes.

## DFA Mathematics on AES-128 Round 9/10

When a single-byte fault $\delta \in [1, 255]$ is injected into state byte 0 after MixColumns in Round 9:
1. The fault propagates through Round 10 ShiftRows and SubBytes to affect 4 ciphertext bytes $(C_0, C_7, C_{12}, C_{13})$:
   $$D_i = C_i \oplus C^*_i \quad \text{for } i \in \{0, 7, 12, 13\}$$
   Where $C_i$ is normal ciphertext byte, $C^*_i$ is faulty ciphertext byte.
2. For each byte position $i$, the candidate 10th-round subkey byte $K_{10, i} \in [0, 255]$ must satisfy the S-Box non-linear differential equation:
   $$\text{SBox}^{-1}(C_i \oplus K_{10, i}) \oplus \text{SBox}^{-1}(C^*_i \oplus K_{10, i}) = f_i$$
   Where vector $f = (2\delta, \delta, \delta, 3\delta)$ in Galois Field $GF(2^8)$ with reduction polynomial $X^8 + X^4 + X^3 + X + 1$ ($0x11b$).

## Input Schema (`tests/dfa_pairs.json`)

```json
{
  "normal_ciphertext": "3243f6a8885a308d313198a2e0370734",
  "faulty_ciphertexts": [
    {
      "faulted_byte_index": 0,
      "ciphertext": "a143f6a8885a308d313198a2e0370734"
    }
  ],
  "target_byte_index": 0
}
```

## Objective

Write a Python 3 script `solution.py` with the class `AESDFARecovery`:
```python
class AESDFARecovery:
    def recover_subkey_byte(self, filepath: str) -> dict:
        # filepath: path to dfa_pairs.json
        # returns: dict {"target_byte_index": int, "candidate_key_byte": int_0_to_255, "candidate_hex": "0x.."}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/dfa_result.json`.

## Constraints
- **Python Standard Library Only** (`json`, `os`, `sys`).
