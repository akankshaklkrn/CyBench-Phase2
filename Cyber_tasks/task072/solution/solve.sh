#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import struct
import hashlib
import json
import os

MAGIC = b"SGXQ"

class AttestationEngine:
    def verify_quote(self, quote_path: str) -> dict:
        with open(quote_path, 'rb') as f:
            data = f.read()
            
        if len(data) < 16:
            return {"valid_header": False, "mrenclave": ""}
            
        magic = data[0:4]
        if magic != MAGIC:
            return {"valid_header": False, "mrenclave": ""}
            
        version, att_type, num_pages = struct.unpack("<HHI", data[4:12])
        reserved = struct.unpack("<I", data[12:16])[0]
        
        if version != 2 or att_type != 1 or reserved != 0:
            return {"valid_header": False, "mrenclave": ""}
            
        offset = 16
        H_curr = bytes([0] * 32)
        
        for _ in range(num_pages):
            if offset + 36 > len(data):
                return {"valid_header": False, "mrenclave": ""}
                
            addr, flags = struct.unpack("<QI", data[offset:offset + 12])
            c_hash = data[offset + 12:offset + 36]
            offset += 36
            
            page_bytes = struct.pack("<QI", addr, flags) + c_hash
            H_curr = hashlib.sha256(H_curr + page_bytes).digest()
            
        return {"valid_header": True, "mrenclave": H_curr.hex()}

if __name__ == "__main__":
    qp = "/tests/quote.bin"
    if not os.path.exists(qp):
        qp = "/Users/jatinjena/Downloads/tasknew/task072/tests/quote.bin"
    engine = AttestationEngine()
    res = engine.verify_quote(qp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/attestation_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
