# Task 067: Implement AES-128 Encryption from Scratch

You are a cryptography researcher who must implement the **AES-128 (Advanced Encryption Standard)** block cipher entirely from scratch in Python. You may **NOT** use any cryptographic libraries (`cryptography`, `pycryptodome`, `Crypto`, `hashlib`, `hmac`, `ssl`, etc.). You may only use Python's standard library (`struct`, `os`, `sys`) and `numpy` for basic array operations.

## Algorithm Specification

AES-128 operates on 128-bit (16-byte) blocks with a 128-bit key. The state is represented as a 4×4 matrix of bytes (column-major order: byte 0 goes to position [0,0], byte 1 to [1,0], byte 2 to [2,0], byte 3 to [3,0], byte 4 to [0,1], etc.).

### Key Expansion
Expand the 16-byte key into 44 words (4 bytes each) = 11 round keys:
- Words 0-3 are copied directly from the key
- For word $i \ge 4$:
  - If $i \mod 4 = 0$: $W[i] = W[i-4] \oplus \text{SubWord}(\text{RotWord}(W[i-1])) \oplus \text{Rcon}[i/4]$
  - Otherwise: $W[i] = W[i-4] \oplus W[i-1]$
- **RotWord**: rotate 4 bytes left by 1: `[a,b,c,d] -> [b,c,d,a]`
- **SubWord**: apply S-Box substitution to each byte
- **Rcon**: round constants: `[0x01,0x02,0x04,0x08,0x10,0x20,0x40,0x80,0x1B,0x36]` (only first byte of each word is non-zero)

### S-Box
The AES S-Box is a fixed 256-byte lookup table. You must either:
- Hardcode the standard NIST AES S-Box, OR
- Generate it via multiplicative inverse in GF(2⁸) followed by an affine transformation

The standard S-Box (hex, row-major):
```
63 7c 77 7b f2 6b 6f c5 30 01 67 2b fe d7 ab 76
ca 82 c9 7d fa 59 47 f0 ad d4 a2 af 9c a4 72 c0
b7 fd 93 26 36 3f f7 cc 34 a5 e5 f1 71 d8 31 15
04 c7 23 c3 18 96 05 9a 07 12 80 e2 eb 27 b2 75
09 83 2c 1a 1b 6e 5a a0 52 3b d6 b3 29 e3 2f 84
53 d1 00 ed 20 fc b1 5b 6a cb be 39 4a 4c 58 cf
d0 ef aa fb 43 4d 33 85 45 f9 02 7f 50 3c 9f a8
51 a3 40 8f 92 9d 38 f5 bc b6 da 21 10 ff f3 d2
cd 0c 13 ec 5f 97 44 17 c4 a7 7e 3d 64 5d 19 73
60 81 4f dc 22 2a 90 88 46 ee b8 14 de 5e 0b db
e0 32 3a 0a 49 06 24 5c c2 d3 ac 62 91 95 e4 79
e7 c8 37 6d 8d d5 4e a9 6c 56 f4 ea 65 7a ae 08
ba 78 25 2e 1c a6 b4 c6 e8 dd 74 1f 4b bd 8b 8a
70 3e b5 66 48 03 f6 0e 61 35 57 b9 86 c1 1d 9e
e1 f8 98 11 69 d9 8e 94 9b 1e 87 e9 ce 55 28 df
8c a1 89 0d bf e6 42 68 41 99 2d 0f b0 54 bb 16
```

### Encryption Rounds (10 rounds for AES-128)

1. **Initial Round**: AddRoundKey (XOR state with round key 0)
2. **Rounds 1-9**: SubBytes → ShiftRows → MixColumns → AddRoundKey
3. **Final Round 10**: SubBytes → ShiftRows → AddRoundKey (NO MixColumns)

#### SubBytes
Replace each byte in the state with its S-Box lookup.

#### ShiftRows
- Row 0: no shift
- Row 1: shift left by 1
- Row 2: shift left by 2
- Row 3: shift left by 3

#### MixColumns
Each column is treated as a polynomial over GF(2⁸) and multiplied by the fixed polynomial $\{03\}x^3 + \{01\}x^2 + \{01\}x + \{02\}$:
```
[2 3 1 1] [s0]
[1 2 3 1] [s1]
[1 1 2 3] [s2]
[3 1 1 2] [s3]
```

**GF(2⁸) multiplication** uses the irreducible polynomial $x^8 + x^4 + x^3 + x + 1$ (0x11B):
- `xtime(a)`: left shift by 1; if bit 7 was set, XOR with 0x1B
- Multiply by 2: `xtime(a)`
- Multiply by 3: `xtime(a) ^ a`

#### AddRoundKey
XOR each byte of the state with the corresponding byte of the round key.

## Implementation Requirements

Write a Python 3 script `solution.py` with the class:
```python
class AES128:
    def encrypt_block(self, plaintext: bytes, key: bytes) -> bytes:
        # plaintext: 16 bytes, key: 16 bytes
        # returns: 16 bytes ciphertext
        pass
```

Your script must also, when run directly, read `tests/test_vectors.csv`, encrypt each plaintext with its key, and write results to `/src/results.csv` in format: `plaintext_hex,key_hex,ciphertext_hex`.

## Difficulty Warning

The MixColumns step requires correct GF(2⁸) arithmetic. The state matrix is **column-major**. The key schedule Rcon values must be in the correct positions. A single error in ANY of these will cause EVERY ciphertext to be wrong.
