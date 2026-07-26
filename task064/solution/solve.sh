#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import sys

SBOX = [(x * 31 + 17) & 0xFF for x in range(256)]

class LZBitDecompressor:
    def decompress(self, data: bytes) -> str:
        seed_a = data[0] | (data[1] << 8)
        seed_b = data[2] | (data[3] << 8)
        
        mask_a = 0xB400
        mask_b = 0xE100
        
        R_A = seed_a
        R_B = seed_b
        
        # Read bits from byte 4 onwards
        enc_bits = []
        for byte_val in data[4:]:
            for i in range(8):
                enc_bits.append((byte_val >> i) & 1)
                
        bit_idx = 0
        
        def decrypt_bit(context):
            nonlocal bit_idx, R_A, R_B
            if bit_idx >= len(enc_bits):
                return 0
            b_enc = enc_bits[bit_idx]
            bit_idx += 1
            
            if context == 'flag':
                b_out = R_A & 1
            elif context == 'literal':
                b_out = (R_A ^ R_B) & 1
            elif context == 'dist':
                b_out = R_B & 1
            elif context == 'len':
                b_out = (R_A & R_B) & 1
            else:
                raise ValueError(f"Unknown context {context}")
                
            b_clean = b_enc ^ b_out
            
            # Step R_A
            R_A_prev = R_A
            R_A_next = (R_A >> 1) & 0xFFFF
            if b_out == 1:
                R_A_next ^= mask_a
            R_A_next ^= ((R_B & 0xF) * (R_A & 0xF))
            R_A_next ^= (b_clean << 15)
            R_A = R_A_next & 0xFFFF
            
            # Step R_B
            R_B_next = (R_B >> 1) & 0xFFFF
            if (R_A_prev & 1) == 1:
                R_B_next ^= mask_b
            R_B_next ^= (b_clean << 15)
            R_B = R_B_next & 0xFFFF
            
            return b_clean
            
        def mutate_sbox():
            nonlocal R_A, R_B
            L_A, H_A = R_A & 0xFF, (R_A >> 8) & 0xFF
            L_B, H_B = R_B & 0xFF, (R_B >> 8) & 0xFF
            
            R_A_new = ((SBOX[L_B] ^ H_A) & 0xFF) | (((SBOX[H_B] ^ L_A) & 0xFF) << 8)
            R_B_new = ((SBOX[L_A] ^ H_B) & 0xFF) | (((SBOX[H_A] ^ L_B) & 0xFF) << 8)
            
            R_A = R_A_new
            R_B = R_B_new
            
        def get_n_bits(n, context):
            val = 0
            for i in range(n):
                val |= (decrypt_bit(context) << i)
            return val
            
        output = []
        while bit_idx < len(enc_bits):
            flag = decrypt_bit('flag')
            if flag == 0:
                char_code = get_n_bits(8, 'literal')
                mutate_sbox()
                output.append(chr(char_code))
            else:
                dist = get_n_bits(10, 'dist')
                length_raw = get_n_bits(6, 'len')
                mutate_sbox()
                
                if dist == 0:
                    break
                length = length_raw + 3
                
                for _ in range(length):
                    output.append(output[-dist])
                    
        return "".join(output)
PYEOF
