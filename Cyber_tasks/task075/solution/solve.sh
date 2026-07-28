#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

def sha256_bytes(b):
    return hashlib.sha256(b).digest()

class GarbledCircuitEvaluator:
    def evaluate(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        active_wires = {k: bytes.fromhex(v) for k, v in data['active_input_labels'].items()}
        output_map = data['output_wire_map']
        gates = data['gates']
        
        # Evaluate gates topologically
        evaluated_any = True
        while evaluated_any:
            evaluated_any = False
            for gate in gates:
                out_w = gate['out_wire']
                if out_w in active_wires:
                    continue
                
                in_A = gate['in_wire_A']
                in_B = gate['in_wire_B']
                
                if in_A in active_wires and in_B in active_wires:
                    lA = active_wires[in_A]
                    lB = active_wires[in_B]
                    
                    key = sha256_bytes(lA + lB)
                    
                    # Try decrypting 4 garbled entries
                    for hex_entry in gate['garbled_table']:
                        enc_bytes = bytes.fromhex(hex_entry)
                        decrypted = bytes([enc_bytes[i] ^ key[i] for i in range(20)])
                        
                        lOut = decrypted[:16]
                        chk = decrypted[16:20]
                        
                        if sha256_bytes(lOut)[:4] == chk:
                            active_wires[out_w] = lOut
                            evaluated_any = True
                            break
                            
        # Decode output wires
        for out_w, val_map in output_map.items():
            if out_w in active_wires:
                active_hex = active_wires[out_w].hex()
                for bit_str, label_hex in val_map.items():
                    if active_hex == label_hex:
                        return {"output_bit": int(bit_str), "output_label": active_hex}
                        
        return {"output_bit": -1, "output_label": ""}

if __name__ == "__main__":
    fp = "/tests/garbled_circuit.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task075/tests/garbled_circuit.json"
    evaluator = GarbledCircuitEvaluator()
    res = evaluator.evaluate(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/gc_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
