# Task 064: Non-Linear Dual-State Cross-Coupled LZ-Bit Decompressor

You have intercepted an ultra-secure compressed and scrambled binary payload (`tests/compressed.bin`). Reverse engineering reveals it combines a **Non-Linear Dual-State Cross-Coupled Shift Register (NLFSR)** cipher engine directly intertwined with a bit-aligned **LZ77 decompression engine**.

Your objective is to write a Python 3 script `solution.py` containing a class `LZBitDecompressor` that simultaneously descrambles and decompresses this payload to retrieve the original ASCII string.

## Bit-Stream Parsing & Little-Endian Packing

The file is a contiguous stream of bits packed into bytes in **Little-Endian** order (Bit 0 is the LSB of Byte 0, Bit 7 is the MSB of Byte 0, Bit 8 is the LSB of Byte 1).
When extracting an $N$-bit integer from the stream, the first bit extracted represents the Least Significant Bit (LSB) of the integer, and the $N$-th bit represents the MSB.

## Phase 1: Cryptographic Engine Setup

The very first **4 bytes** (32 bits) of `compressed.bin` contain two unencrypted 16-bit little-endian seed values:
- `Seed_A` (Bytes 0-1): Initialize 16-bit register $R_A = \text{Seed\_A}$.
- `Seed_B` (Bytes 2-3): Initialize 16-bit register $R_B = \text{Seed\_B}$.

Encryption/decryption begins from **Byte 4** onwards.

## Phase 2: Context-Dependent Bit Decryption & NLFSR Stepping

For every bit $b_{enc}$ read from the payload, you must determine its **Context Type** based on what LZ77 token component is being read:

1. **Flag Bit** (1 bit): $b_{out} = R_A \& 1$
2. **Literal Byte Bits** (8 bits): $b_{out} = (R_A \oplus R_B) \& 1$
3. **Match Distance Bits** (10 bits): $b_{out} = R_B \& 1$
4. **Match Length Bits** (6 bits): $b_{out} = (R_A \ \& \ R_B) \& 1$

Decrypt the bit:
$$b_{clean} = b_{enc} \oplus b_{out}$$

### Stepping the Coupled Shift Registers
Immediately after decrypting each bit $b_{clean}$, step both registers $R_A$ and $R_B$ in this exact order:

**1. Step $R_A$**:
- $R_A' = (R_A \gg 1) \& 0xFFFF$
- If $b_{out} == 1$, apply polynomial mask `MASK_A = 0xB400`: $R_A' = R_A' \oplus \text{MASK\_A}$
- Add Non-Linear Term: $R_A' = R_A' \oplus ((R_B \& 0xF) \times (R_A \& 0xF))$
- CFB Feedback: $R_A' = R_A' \oplus (b_{clean} \ll 15)$
- $R_A = R_A' \& 0xFFFF$

**2. Step $R_B$**:
- $R_B' = (R_B \gg 1) \& 0xFFFF$
- If $(R_A \& 1) == 1$, apply polynomial mask `MASK_B = 0xE100`: $R_B' = R_B' \oplus \text{MASK\_B}$
- CFB Feedback: $R_B' = R_B' \oplus (b_{clean} \ll 15)$
- $R_B = R_B' \& 0xFFFF$

## Phase 3: Post-Token Cross-Coupled S-Box Mutation

Immediately after parsing a **complete LZ77 token** (either a Literal Token: 1 flag + 8 literal bits, OR a Match Token: 1 flag + 10 distance + 6 length bits), you MUST mutate the state of $R_A$ and $R_B$ using an 8-bit S-Box.

The 256-byte S-Box is defined as: `SBox[x] = (x * 31 + 17) & 0xFF`.

To perform the mutation:
- Extract 8-bit halves:
  - $L_A = R_A \& 0xFF$, $H_A = (R_A \gg 8) \& 0xFF$
  - $L_B = R_B \& 0xFF$, $H_B = (R_B \gg 8) \& 0xFF$
- Compute new register values:
  - $R_A^{new} = ((\text{SBox}[L_B] \oplus H_A) \& 0xFF) \ | \ (((\text{SBox}[H_B] \oplus L_A) \& 0xFF) \ll 8)$
  - $R_B^{new} = ((\text{SBox}[L_A] \oplus H_B) \& 0xFF) \ | \ (((\text{SBox}[H_A] \oplus L_B) \& 0xFF) \ll 8)$
- Set $R_A = R_A^{new}$ and $R_B = R_B^{new}$.

## Phase 4: LZ77 Decompression

Using the decrypted $b_{clean}$ bitstream:
- Read 1 **Flag Bit**:
  - If `0`: Read 8 bits for ASCII `char_code`. Append `chr(char_code)` to output string.
  - If `1`: Read 10 bits for `distance`, then 6 bits for `raw_length`.
    - If `distance == 0`: Stop condition (end of stream).
    - Otherwise, `length = raw_length + 3`. Copy `length` bytes from `output[-distance]` to `output`.

## Interface Requirement

Implement the following in `solution.py`:
```python
class LZBitDecompressor:
    def decompress(self, data: bytes) -> str:
        # data: raw bytes read from tests/compressed.bin
        # returns decompressed ASCII string
        pass
```
