#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

def is_prime(n):
    if n < 2: return False
    if n in (2, 3): return True
    if n % 2 == 0 or n % 3 == 0: return False
    d = n - 1
    s = 0
    while d % 2 == 0:
        d //= 2
        s += 1
    for a in (2, 3, 5, 7, 11, 13, 17, 19, 23):
        if n <= a: break
        x = pow(a, d, n)
        if x == 1 or x == n - 1:
            continue
        for _ in range(s - 1):
            x = (x * x) % n
            if x == n - 1:
                break
        else:
            return False
    return True

def next_prime(n):
    while not is_prime(n):
        n += 1
    return n

class VDFVerifier:
    def verify(self, filepath: str) -> bool:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        N = int(data['N'])
        x = int(data['x'])
        T = int(data['T'])
        y = int(data['y'])
        pi = int(data['pi'])
        
        # Fiat-Shamir challenge q
        raw_str = f"{N}:{x}:{y}:{T}"
        h = hashlib.sha256(raw_str.encode()).hexdigest()
        q = next_prime(int(h, 16) % 1000000 + 1000)
        
        # r = 2^T mod q
        r = pow(2, T, q)
        
        # y_check = (pi^q * x^r) mod N
        y_check = (pow(pi, q, N) * pow(x, r, N)) % N
        
        return y_check == y

if __name__ == "__main__":
    fp = "/tests/vdf_proof.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task070/tests/vdf_proof.json"
    verifier = VDFVerifier()
    res = verifier.verify(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/vdf_result.json", "w") as f:
        json.dump({"valid": res}, f, indent=2)
PYEOF
cd /src && python3 solution.py
