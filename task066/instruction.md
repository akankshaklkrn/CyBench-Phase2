# Task 066: Differential Power Analysis (DPA) Side-Channel Attack

You are a hardware security researcher performing a **Differential Power Analysis (DPA)** attack to recover a secret 16-byte key from an AES-128 cryptographic microchip.

## Background & Power Leakage Model

During AES-128 encryption, the S-Box operation in Round 1 processes each byte of state:
$$S[p_i \oplus k_i]$$
Where $p_i$ is byte $i$ of the plaintext and $k_i$ is byte $i$ of the secret key ($0 \le i < 16$).

The physical power consumption of the chip is proportional to the number of $1$ bits set in the intermediate S-Box output byte (the **Hamming Weight**):
$$\text{Power}(p_i, k_i) = \text{HammingWeight}(S[p_i \oplus k_i]) + \text{noise}$$

By analyzing the statistical correlation between calculated Hamming Weight hypotheses and the measured power traces across thousands of encryptions, you can isolate the correct byte for all 16 key bytes.

## Input Files

1. `tests/plaintexts.bin`: $5000 \times 16$ bytes of raw unencrypted input blocks ($5,000$ encryptions).
2. `tests/power_traces.bin`: $5000 \times 500$ 32-bit floating point values (`float32` binary matrix). Each row contains 500 power consumption samples taken during one encryption.

## Pearson Correlation Coefficient

For each candidate key byte value $g \in [0, 255]$ and each key byte position $i \in [0, 15]$:
1. Compute the hypothesis vector $h^{(g)}$ of length 5,000:
   $$h^{(g)}[m] = \text{HammingWeight}(S[p_m[i] \oplus g]) \quad \text{for } m = 0 \dots 4999$$
2. Calculate the Pearson correlation coefficient $\rho(h^{(g)}, t_j)$ against power trace column $j \in [0, 499]$:
   $$\rho(x, y) = \frac{\sum (x - \bar{x})(y - \bar{y})}{\sqrt{\sum (x - \bar{x})^2 \sum (y - \bar{y})^2}}$$
3. The candidate key byte $g$ that yields the **highest absolute correlation peak** $|\rho|$ across all 500 trace points is the correct key byte $k_i$.

## Implementation

Write a Python 3 script `solution.py` with the class `DPAAttack`:
```python
class DPAAttack:
    def recover_key(self, plaintexts_path: str, traces_path: str) -> str:
        # returns: 16-byte key formatted as a 32-character lowercase hex string
        # e.g., '00112233445566778899aabbccddeeff'
        pass
```

When run directly, write the recovered 32-char hex string to `/src/recovered_dpa_key.txt`.

## Requirements
- **Python Standard Library Only** (`struct`, `os`, `sys`, `math`).
- No `numpy`, `scipy`, or machine learning libraries.
