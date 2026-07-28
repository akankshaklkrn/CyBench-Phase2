# Task 068: Automated ROP Chain Payload Synthesizer

You are a binary security researcher synthesizing a 64-bit Return-Oriented Programming (ROP) exploit payload to bypass NX/DEP mitigations.

## Objective

Given a JSON file `tests/gadgets.json` containing:
1. Target register values required to execute `execve("/bin/sh", 0, 0)`:
   - `rax = 59` (`0x3b`, `SYS_execve`)
   - `rdi = 0x404050` (pointer to string `"/bin/sh\x00"`)
   - `rsi = 0x0`
   - `rdx = 0x0`
2. A dictionary of available ROP gadgets with 64-bit virtual memory addresses (`0x400xxx`).
3. Overflow padding offset $N = 64$ bytes to reach the saved Return Address (`saved_rip`).

Synthesize a raw binary ROP payload that:
1. Fills the first 64 bytes with `A` (`0x41`) padding.
2. Constructs a sequence of 64-bit little-endian gadget addresses (`<Q` in `struct.pack`) and immediate stack values to populate `rax`, `rdi`, `rsi`, `rdx`.
3. Ends with the gadget address for `syscall` (`0x0f 0x05`).

## Input JSON Format (`tests/gadgets.json`)

```json
{
  "overflow_offset": 64,
  "target_state": {
    "rax": 59,
    "rdi": 4210768,
    "rsi": 0,
    "rdx": 0
  },
  "gadgets": {
    "pop_rax_ret": "0x0000000000401111",
    "pop_rdi_ret": "0x0000000000401122",
    "pop_rsi_ret": "0x0000000000401133",
    "pop_rdx_ret": "0x0000000000401144",
    "syscall": "0x0000000000401155"
  }
}
```

## Implementation

Write a Python 3 script `solution.py` with the class `ROPSynthesizer`:
```python
class ROPSynthesizer:
    def synthesize_payload(self, filepath: str) -> bytes:
        # filepath: path to gadgets.json
        # returns: raw bytearray/bytes containing full ROP exploit payload
        pass
```

When run directly (`python3 solution.py`), write the binary payload to `/src/rop_payload.bin`.

## Rules & Requirements
- **Python Standard Library Only** (`struct`, `json`, `os`, `sys`).
- All 64-bit addresses and stack values must be encoded as 8-byte little-endian unsigned integers.
