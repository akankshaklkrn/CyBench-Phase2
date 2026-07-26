# Task 075: Multi-Party Computation — Yao's Garbled Circuit Evaluator

You are an MPC engineer building an evaluator for **Yao's Garbled Circuit (GC)**, enabling secure two-party computation (2PC) over encrypted wire labels.

## Garbled Gate Decryption Algorithm

In Yao's Garbled Circuit, each wire $W$ has two secret 128-bit labels: $L_{W, 0}$ (representing bit 0) and $L_{W, 1}$ (representing bit 1).

A 2-input garbled gate with input wires $A, B$ and output wire $C$ contains a garbled table of 4 encrypted entries.
For active input wire labels $L_A$ and $L_B$, the correct garbled entry is decrypted using double SHA-256 key derivation:
$$\text{Key}_{A,B} = \text{SHA256}(L_A \parallel L_B)$$
$$\text{DecryptedPayload} = \text{GarbledEntry} \oplus \text{Key}_{A,B}$$

If decryption succeeds, the decrypted payload contains:
$$L_C \parallel \text{Checksum}$$
Where $\text{Checksum} = \text{SHA256}(L_C)[:4]$ (first 4 bytes of SHA-256 hash of output label $L_C$). Exactly one of the 4 garbled entries in the table will yield a valid checksum matching its output label $L_C$.

## Input Schema (`tests/garbled_circuit.json`)

```json
{
  "active_input_labels": {
    "wire_0": "3a7b...",
    "wire_1": "9f2c..."
  },
  "output_wire_map": {
    "wire_4": {
      "0": "112233...",
      "1": "445566..."
    }
  },
  "gates": [
    {
      "gate_id": "g0",
      "in_wire_A": "wire_0",
      "in_wire_B": "wire_1",
      "out_wire": "wire_2",
      "garbled_table": [
        "hex_entry_0",
        "hex_entry_1",
        "hex_entry_2",
        "hex_entry_3"
      ]
    }
  ]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `GarbledCircuitEvaluator`:
```python
class GarbledCircuitEvaluator:
    def evaluate(self, filepath: str) -> dict:
        # filepath: path to garbled_circuit.json
        # returns: dict {"output_bit": int_0_or_1, "output_label": "hex_string"}
        pass
```

When run directly (`python3 solution.py`), write the output dictionary to `/src/gc_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`hashlib`, `json`, `os`, `sys`).
- All wire labels and garbled entries are 32-character lowercase hex strings (16 bytes).
