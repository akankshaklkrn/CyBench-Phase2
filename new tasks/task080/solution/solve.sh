#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

def hash_to_field(elem_str: str, p: int) -> int:
    return int(hashlib.sha256(elem_str.encode()).hexdigest(), 16) % p

class PSIProtocolEngine:
    def compute_intersection(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = data['prime']
        r = data['client_secret_r']
        s = data['server_secret_s']
        client_set = data['client_set']
        server_set = data['server_set']
        
        # 1. Client blinds hashes: h(x)^r mod p
        client_blinded = [pow(hash_to_field(x, p), r, p) for x in client_set]
        
        # 2. Server evaluates client blinded: (h(x)^r)^s = h(x)^(r*s) mod p
        server_eval_client = [pow(c_b, s, p) for c_b in client_blinded]
        
        # Server computes its own hashes: h(y)^s mod p
        server_local = {y: pow(hash_to_field(y, p), s, p) for y in server_set}
        server_local_set = set(server_local.values())
        
        # 3. Client unblinds: (h(x)^(r*s))^(r^-1 mod p-1) = h(x)^s mod p
        r_inv = pow(r, -1, p - 1)
        client_oprf = [pow(s_e, r_inv, p) for s_e in server_eval_client]
        
        # 4. Find matches
        intersected = []
        for i, x in enumerate(client_set):
            if client_oprf[i] in server_local_set:
                intersected.append(x)
                
        return {
            "intersection_size": len(intersected),
            "intersected_elements": sorted(intersected)
        }

if __name__ == "__main__":
    fp = "/tests/psi_data.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task080/tests/psi_data.json"
    engine = PSIProtocolEngine()
    res = engine.compute_intersection(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/psi_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
