#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import struct
import os

BPF_LD_W_ABS = 0x20
BPF_JMP_JEQ_K = 0x15
BPF_RET_K = 0x06
SECCOMP_RET_ALLOW = 0x7FFF0000

class SeccompEvaluator:
    def evaluate_policy(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        bytecode_raw = bytes.fromhex(data['bpf_bytecode'])
        evals = data['syscall_evaluations']
        
        insns = []
        for i in range(0, len(bytecode_raw), 8):
            code, jt, jf, k = struct.unpack("<HBBI", bytecode_raw[i:i+8])
            insns.append((code, jt, jf, k))
            
        results = []
        for eval_req in evals:
            nr = eval_req['syscall_nr']
            arch = eval_req['arch']
            
            pc = 0
            A = 0
            ret_action = None
            
            while pc < len(insns):
                code, jt, jf, k = insns[pc]
                if code == BPF_LD_W_ABS:
                    if k == 0:
                        A = nr
                    elif k == 4:
                        A = arch
                    pc += 1
                elif code == BPF_JMP_JEQ_K:
                    if A == k:
                        pc += 1 + jt
                    else:
                        pc += 1 + jf
                elif code == BPF_RET_K:
                    ret_action = k
                    break
                else:
                    pc += 1
                    
            action_str = "ALLOW" if ret_action == SECCOMP_RET_ALLOW else "KILL"
            results.append({"syscall_nr": nr, "action": action_str})
            
        return {"audit_results": results}

if __name__ == "__main__":
    fp = "/tests/seccomp_policy.json"
    if not os.path.exists(fp):
        fp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "seccomp_policy.json")
    evaluator = SeccompEvaluator()
    res = evaluator.evaluate_policy(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/seccomp_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
