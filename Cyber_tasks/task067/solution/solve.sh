#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class ModuleLWEDecryptor:
    def decrypt(self, filepath: str) -> str:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        n = data['n']
        q = data['q']
        
        s0 = data['secret_key']['s0']
        s1 = data['secret_key']['s1']
        
        u0 = data['ciphertext']['u0']
        u1 = data['ciphertext']['u1']
        v = data['ciphertext']['v']
        
        # Polynomial multiplication mod (X^n + 1, q)
        def poly_mul(a, b):
            res = [0] * (2 * n)
            for i in range(n):
                for j in range(n):
                    res[i + j] = (res[i + j] + a[i] * b[j]) % q
            out = [0] * n
            for i in range(n):
                out[i] = (res[i] - res[i + n]) % q
            return out
            
        su0 = poly_mul(s0, u0)
        su1 = poly_mul(s1, u1)
        
        m_noisy = [(v[i] - (su0[i] + su1[i])) % q for i in range(n)]
        
        HALF_Q = (q + 1) // 2
        bits = []
        for val in m_noisy:
            # Check distance to HALF_Q (1665)
            diff = abs(val - HALF_Q)
            if diff < HALF_Q // 2:
                bits.append(1)
            else:
                bits.append(0)
                
        # Reassemble bits into bytes
        bytes_out = bytearray(32)
        for i in range(32):
            b_val = 0
            for bit_idx in range(8):
                b_val |= (bits[i * 8 + bit_idx] << bit_idx)
            bytes_out[i] = b_val
            
        return bytes_out.decode('utf-8', errors='ignore').rstrip('\x00')

if __name__ == "__main__":
    fp = "/tests/lwe_ciphertext.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task067/tests/lwe_ciphertext.json"
    decryptor = ModuleLWEDecryptor()
    msg = decryptor.decrypt(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/decrypted_pqc_msg.txt", "w") as f:
        f.write(msg + "\n")
PYEOF
cd /src && python3 solution.py
