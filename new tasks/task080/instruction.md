# Task 080: OPRF Private Set Intersection (PSI) Protocol Engine

You are a privacy-preserving cryptography engineer implementing an **Oblivious Pseudorandom Function (OPRF) Private Set Intersection (PSI)** protocol over finite prime field $\mathbb{F}_p$ ($p = 65537$).

## OPRF Private Set Intersection Mathematics

Two parties, Client $A$ with set $S_A = \{x_1, \dots, x_m\}$ and Server $B$ with set $S_B = \{y_1, \dots, y_n\}$, compute $|S_A \cap S_B|$ without revealing non-intersecting elements.

1. **Hash-to-Field Mapping**:
   For element string $e$:
   $$h(e) = \text{int}(\text{SHA256}(e), 16) \pmod p$$
2. **Client Blinding (Secret key $r \in [1, p-1]$)**:
   $$A_{blind}(x_i) = h(x_i)^r \pmod p$$
3. **Server Evaluation (Secret key $s \in [1, p-1]$)**:
   - Server evaluates client blinded hashes:
     $$B_{evaluated}(x_i) = (A_{blind}(x_i))^s = h(x_i)^{r \cdot s} \pmod p$$
   - Server evaluates its own set hashes:
     $$B_{local}(y_j) = h(y_j)^s \pmod p$$
4. **Client Unblinding**:
   - Client computes modular inverse $r^{-1} \pmod{p-1}$ using Euler's totient.
   - Client unblinds server evaluated elements:
     $$OPRF(x_i) = (B_{evaluated}(x_i))^{r^{-1}} = (h(x_i)^{r \cdot s})^{r^{-1}} \equiv h(x_i)^s \pmod p$$
5. **Intersection Computation**:
   - Client compares $OPRF(x_i)$ against Server's set $\{B_{local}(y_j)\}$.
   - The intersection count $|S_A \cap S_B|$ is the number of matching values.

## Input Schema (`tests/psi_data.json`)

```json
{
  "prime": 65537,
  "client_secret_r": 12345,
  "server_secret_s": 54321,
  "client_set": ["user_alice@domain.com", "user_bob@domain.com", ...],
  "server_set": ["user_bob@domain.com", "user_charlie@domain.com", ...]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `PSIProtocolEngine`:
```python
class PSIProtocolEngine:
    def compute_intersection(self, filepath: str) -> dict:
        # filepath: path to psi_data.json
        # returns: dict {"intersection_size": int_count, "intersected_elements": ["item1", ...]}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/psi_result.json`.

## Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `os`, `sys`).
