#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class LatticeZKVerifier:
    def verify_proof(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        N = data['N']
        q = data['q']
        beta = data['beta']
        c = data['c']
        s = data['s']
        y = data['y']
        
        # Ring multiplication c * s mod X^N + 1 mod q
        res = [0] * (2 * N)
        for i in range(N):
            for j in range(N):
                res[i + j] = (res[i + j] + c[i] * s[j]) % q
                
        cs = [0] * N
        for i in range(N):
            cs[i] = (res[i] - res[i + N]) % q
            
        z = [(y[i] + cs[i]) % q for i in range(N)]
        
        half = q // 2
        z_centered = [((zi + half) % q) - half for zi in z]
        norm_inf = max(abs(zi) for zi in z_centered)
        
        return {
            "bound_valid": (norm_inf <= beta),
            "z_coefficients": z,
            "norm_infinity": norm_inf
        }

if __name__ == "__main__":
    fp = "/tests/lattice_proof.json"
    if not os.path.exists(fp):
        fp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "lattice_proof.json")
    verifier = LatticeZKVerifier()
    res = verifier.verify_proof(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/lattice_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
