# Task 073: Ciphertext-Policy Attribute-Based Encryption (CP-ABE) Policy Evaluator

You are a cryptographic access control engineer implementing a **Ciphertext-Policy Attribute-Based Encryption (CP-ABE)** access tree evaluator and key reconstruction module over finite field $\mathbb{F}_p$ ($p = 65537$).

## Access Tree & Policy Evaluation

In CP-ABE, ciphertexts are encrypted under a boolean access policy tree $T$ containing leaf attributes and interior threshold/AND/OR logic gates.

1. **Policy Tree Schema**:
   - `op`: `"AND"`, `"OR"`, or `"LEAF"`.
   - `attr`: Attribute name string (only present when `op == "LEAF"`).
   - `children`: List of child policy node objects.

2. **User Secret Key Attributes**:
   A user possesses a set of attributes $S = \{\text{"ROLE\_ADMIN"}, \text{"DEPT\_FINANCE"}, \dots\}$.

3. **Polynomial Share & Lagrange Combination**:
   - Each leaf attribute node $v$ with attribute $A \in S$ provides a share component $C_v$.
   - For an `"AND"` gate with 2 children, both children must be satisfied.
   - For an `"OR"` gate, at least 1 child must be satisfied.
   - The master secret key share $K_{master}$ is computed by combining leaf shares via polynomial evaluation:
     $$K_{master} = \sum_{v \in \text{SatisfyingLeaves}} C_v \cdot L_v \pmod p$$
     Where $L_v = \prod_{j \neq v} \frac{-x_j}{x_v - x_j} \pmod p$ are Lagrange basis coefficients over the satisfying leaf evaluation points $x_v$.

4. **Symmetric Encryption Key Derivation**:
   $$\text{SessionKey} = \text{SHA256}(K_{master} \pmod p) \text{ formatted as 64-character lowercase hex string.}$$

## Input Specification (`tests/abe_data.json`)

```json
{
  "prime": 65537,
  "policy_tree": {
    "op": "AND",
    "children": [
      {"op": "LEAF", "attr": "ROLE_ENGINEER", "x": 1, "C": 1234},
      {
        "op": "OR",
        "children": [
          {"op": "LEAF", "attr": "CLEARANCE_SECRET", "x": 2, "C": 5678},
          {"op": "LEAF", "attr": "CLEARANCE_TOPSECRET", "x": 3, "C": 9999}
        ]
      }
    ]
  },
  "user_attributes": ["ROLE_ENGINEER", "CLEARANCE_TOPSECRET"]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `CPABEEvaluator`:
```python
class CPABEEvaluator:
    def decrypt_session_key(self, filepath: str) -> dict:
        # filepath: path to abe_data.json
        # returns: dict {"satisfied": bool, "session_key": "64_char_hex_string"}
        pass
```

When run directly (`python3 solution.py`), write the result dictionary to `/src/abe_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `os`, `sys`).
- Lagrange interpolation coefficients must be calculated modulo $p = 65537$.
