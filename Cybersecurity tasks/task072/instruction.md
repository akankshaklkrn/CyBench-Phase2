# Task 072: Enclave Attestation & Cumulative Page Measurement Engine

You are a Confidential Computing security engineer implementing an Intel SGX / TDX **Remote Attestation Quote Parser and Measurement Verification Engine**.

## Background

When a secure enclave boots inside a hardware Trusted Execution Environment (TEE), the hardware processor measures every memory page loaded into the enclave space.

### Binary Header & Structure (`tests/quote.bin`)
1. **Header (16 bytes)**:
   - `magic` (4 bytes): `0x53475851` (`"SGXQ"`)
   - `version` (2 bytes): `2`
   - `attestation_type` (2 bytes): `1` (ECDSA P-256)
   - `num_pages` (4 bytes): Number of measured memory pages $M$.
   - `reserved` (4 bytes): `0x00000000`.

2. **Page Measurements** ($M \times 36$ bytes):
   For each page $i \in [0, M-1]$:
   - `page_address` (8 bytes, uint64 little-endian)
   - `page_flags` (4 bytes, uint32 little-endian, e.g. R/W/X permissions)
   - `page_content_hash` (24 bytes): First 24 bytes of the page's SHA-256 content digest.

3. **Cumulative Measurement Hash Formula**:
   - Initialize cumulative hash state $H_0 = \text{bytes}([0] \times 32)$.
   - For each page measurement $i$:
     $$H_{i+1} = \text{SHA256}(H_i \parallel \text{page\_address}_i \parallel \text{page\_flags}_i \parallel \text{page\_content\_hash}_i)$$
   - Final Enclave Measurement Hash $MRESTART = H_M$ formatted as a **64-character lowercase hex string**.

## Objective

Write a Python 3 script `solution.py` with the class `AttestationEngine`:
```python
class AttestationEngine:
    def verify_quote(self, quote_path: str) -> dict:
        # quote_path: path to quote.bin
        # returns: dict {"valid_header": bool, "mrenclave": "64_char_hex_hash"}
        pass
```

When run directly (`python3 solution.py`), write the output dictionary to `/src/attestation_result.json`.

## Requirements
- **Python Standard Library Only** (`struct`, `hashlib`, `json`, `os`, `sys`).
- Unpack binary structs correctly in little-endian format (`<`).
