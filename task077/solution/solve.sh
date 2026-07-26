#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class RSAAccumulatorVerifier:
    def verify_proofs(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        N = int(data['N'])
        g = int(data['g'])
        V = int(data['V'])
        
        # 1. Membership test: Wy^py == V (mod N)
        mem_data = data['membership_test']
        py = int(mem_data['py'])
        Wy = int(mem_data['W'])
        
        mem_check = (pow(Wy, py, N) == V)
        
        # 2. Non-membership test: V^d * W_non^pz == g (mod N)
        non_mem_data = data['non_membership_test']
        pz = int(non_mem_data['pz'])
        d = int(non_mem_data['d'])
        W_non = int(non_mem_data['W_non'])
        
        part1 = pow(V, d, N)
        part2 = pow(W_non, pz, N)
        non_mem_check = ((part1 * part2) % N == g)
        
        return {
            "membership_valid": mem_check,
            "non_membership_valid": non_mem_check
        }

if __name__ == "__main__":
    fp = "/tests/accumulator_proof.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task077/tests/accumulator_proof.json"
    verifier = RSAAccumulatorVerifier()
    res = verifier.verify_proofs(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/accumulator_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
