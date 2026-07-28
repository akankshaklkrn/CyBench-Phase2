#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

class BLSVerifier:
    def verify_aggregate(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = int(data['prime'])
        g = int(data['generator'])
        msg = data['message']
        pks = [int(pk) % p for pk in data['public_keys']]
        agg_sig = int(data['aggregated_signature']) % p
        
        m_hash = int(hashlib.sha256(msg.encode()).hexdigest(), 16) % p
        agg_pk = sum(pks) % p
        
        # Verify (agg_sig * G) == (agg_pk * m_hash) mod p
        lhs = (agg_sig * g) % p
        rhs = (agg_pk * m_hash) % p
        
        valid = (lhs == rhs)
        return {"valid": valid, "aggregated_pk": str(agg_pk)}

if __name__ == "__main__":
    fp = "/tests/bls_data.json"
    if not os.path.exists(fp):
        fp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "bls_data.json")
    verifier = BLSVerifier()
    res = verifier.verify_aggregate(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/bls_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
