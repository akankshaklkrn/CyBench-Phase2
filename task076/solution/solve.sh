#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

def sha256_int(s, p):
    return int(hashlib.sha256(s.encode()).hexdigest(), 16) % p

def mod_inv(x, p):
    return pow(x, p - 2, p)

def dot_prod(v1, v2, p):
    return sum((v1[i] * v2[i]) for i in range(len(v1))) % p

class BulletproofVerifier:
    def verify_inner_product(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = int(data['prime'])
        N = data['N']
        a_curr = [int(x) % p for x in data['a']]
        b_curr = [int(x) % p for x in data['b']]
        
        L_list = [int(x) % p for x in data['proof']['L']]
        R_list = [int(x) % p for x in data['proof']['R']]
        
        idx = 0
        while len(a_curr) > 1:
            half = len(a_curr) // 2
            a_lo, a_hi = a_curr[:half], a_curr[half:]
            b_lo, b_hi = b_curr[:half], b_curr[half:]
            
            L = L_list[idx]
            R = R_list[idx]
            idx += 1
            
            x = sha256_int(f"{L}:{R}", p)
            x_inv = mod_inv(x, p)
            
            a_curr = [(a_lo[i] * x + a_hi[i] * x_inv) % p for i in range(half)]
            b_curr = [(b_lo[i] * x_inv + b_hi[i] * x) % p for i in range(half)]
            
        c_final = (a_curr[0] * b_curr[0]) % p
        return {"valid": True, "c_final": str(c_final)}

if __name__ == "__main__":
    fp = "/tests/bulletproof_data.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task076/tests/bulletproof_data.json"
    verifier = BulletproofVerifier()
    res = verifier.verify_inner_product(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/bulletproof_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
