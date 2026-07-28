# Task 078: BLS Aggregate Signature & Multi-Key Verifier

You are a blockchain security engineer building a **BLS Aggregate Signature Verifier** over prime field $\mathbb{F}_p$ ($p = 21888242871839275222246405745257275088548364400416034343698204186575808495617$).

## BLS Signature Aggregation Mathematics

In Boneh-Lynn-Shacham (BLS) multi-signatures over a prime field group:
1. $N$ signers have private keys $sk_i \in \mathbb{F}_p$ and public keys $pk_i = (sk_i \cdot G) \pmod p$, where $G = 65537$ is the generator.
2. Each signer signs message hash $m\_hash = \text{int}(\text{SHA256}(\text{message}), 16) \pmod p$:
   $$\sigma_i = (sk_i \cdot m\_hash) \pmod p$$
3. **Aggregated Signature**:
   $$\sigma_{agg} = \left(\sum_{i=1}^N \sigma_i\right) \pmod p$$
4. **Aggregated Public Key**:
   $$PK_{agg} = \left(\sum_{i=1}^N pk_i\right) \pmod p$$
5. **Verification Equation**:
   $$(\sigma_{agg} \cdot G) \equiv (PK_{agg} \cdot m\_hash) \pmod p$$

## Input Schema (`tests/bls_data.json`)

```json
{
  "prime": "21888242871839275222246405745257275088548364400416034343698204186575808495617",
  "generator": 65537,
  "message": "Block header #1048576 state root commitment",
  "public_keys": [123456, 789012, ...],
  "aggregated_signature": "987654321..."
}
```

## Objective

Write a Python 3 script `solution.py` with the class `BLSVerifier`:
```python
class BLSVerifier:
    def verify_aggregate(self, filepath: str) -> dict:
        # filepath: path to bls_data.json
        # returns: dict {"valid": bool, "aggregated_pk": "int_str"}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/bls_result.json`.

## Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `os`, `sys`).
