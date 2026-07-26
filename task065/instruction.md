# Task 065: zk-SNARK R1CS Constraint Verifier & Witness Solver

You are a cryptography engineer validating zero-knowledge SNARK circuits. A Rank-1 Constraint System (R1CS) over a finite scalar field $\mathbb{F}_p$ represents a computation as a system of vector equations:
$$(A \cdot w) \circ (B \cdot w) = C \cdot w \pmod p$$

Where:
- $w = [1, x_1, x_2, \dots, x_m]^T$ is the **witness vector** of length $m+1$.
- $A, B, C$ are $n \times (m+1)$ sparse matrices over $\mathbb{F}_p$.
- $\circ$ denotes the element-wise Hadamard product.
- Prime field modulus $p = 21888242871839275222246405745257275088548364400416034343698204186575808495617$ (the BN254 / alt_bn128 scalar field).

## Input File Format

The file `tests/r1cs_circuit.json` has the following schema:
```json
{
  "prime": "21888242871839275222246405745257275088548364400416034343698204186575808495617",
  "num_variables": 10,
  "num_constraints": 8,
  "public_inputs": [1, 42],
  "A": [[row, col, val_str], ...],
  "B": [[row, col, val_str], ...],
  "C": [[row, col, val_str], ...],
  "partial_witness": {"0": 1, "1": 42, "2": 5, ...}
}
```
- **`partial_witness`**: A dictionary providing values for a subset of witness variables. Variable `0` is always `1`.

## Objective

Write a Python 3 script `solution.py` containing a class `R1CSVerifier`:
```python
class R1CSVerifier:
    def solve_and_verify(self, filepath: str) -> dict:
        # filepath: path to r1cs_circuit.json
        # returns: dict {"valid": bool, "full_witness": [int_val_0, int_val_1, ...]}
        pass
```

### Steps:
1. Parse the sparse matrices $A, B, C$ and the prime modulus $p$.
2. Solve for the remaining unknown witness variables in `partial_witness` so that ALL $n$ constraint equations hold exactly modulo $p$.
3. Compute and return the complete witness vector `full_witness` as a list of integers modulo $p$.
4. Return `{"valid": True, "full_witness": [...]}` if the circuit is fully satisfied, or `{"valid": False, "full_witness": []}` if unsatisfiable.

When run directly (`python3 solution.py`), write the output dictionary to `/src/r1cs_result.json`.

## Constraints & Rules
- **Python Standard Library Only** (no `sympy`, `numpy`, `scipy`, `circom`, or `snarkjs`).
- Modular inverse calculations must use Fermat's Little Theorem ($a^{p-2} \pmod p$) or the Extended Euclidean Algorithm.
- All matrix-vector multiplications must be computed modulo $p$.
