#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class FHECKKSMultiplier:
    def multiply_and_rescale(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        N = data['N']
        Q = data['Q']
        scale = data['scale']
        
        cA_c0 = data['cA']['c0']
        cA_c1 = data['cA']['c1']
        cB_c0 = data['cB']['c0']
        cB_c1 = data['cB']['c1']
        
        evk0 = data['evk']['evk0']
        evk1 = data['evk']['evk1']
        
        def poly_mul(a, b):
            res = [0] * (2 * N)
            for i in range(N):
                for j in range(N):
                    res[i + j] = (res[i + j] + a[i] * b[j]) % Q
            out = [0] * N
            for i in range(N):
                out[i] = (res[i] - res[i + N]) % Q
            return out
            
        def poly_add(a, b):
            return [(a[i] + b[i]) % Q for i in range(N)]
            
        def poly_rescale(a):
            return [round(x / scale) % Q for x in a]
            
        # Tensor Multiplication
        d0 = poly_mul(cA_c0, cB_c0)
        d1 = poly_add(poly_mul(cA_c0, cB_c1), poly_mul(cA_c1, cB_c0))
        d2 = poly_mul(cA_c1, cB_c1)
        
        # Relinearization
        relin0 = poly_rescale(poly_mul(d2, evk0))
        relin1 = poly_rescale(poly_mul(d2, evk1))
        
        c0_prime = poly_add(d0, relin0)
        c1_prime = poly_add(d1, relin1)
        
        # Scale Reduction
        c0 = poly_rescale(c0_prime)
        c1 = poly_rescale(c1_prime)
        
        return {"c0": c0, "c1": c1}

if __name__ == "__main__":
    fp = "/tests/fhe_data.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task069/tests/fhe_data.json"
    multiplier = FHECKKSMultiplier()
    res = multiplier.multiply_and_rescale(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/fhe_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
