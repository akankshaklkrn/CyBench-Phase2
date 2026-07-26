#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import hashlib
import os

class CPABEEvaluator:
    def decrypt_session_key(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = data['prime']
        policy_tree = data['policy_tree']
        user_attrs = set(data['user_attributes'])
        
        def evaluate_node(node):
            op = node['op']
            if op == 'LEAF':
                if node['attr'] in user_attrs:
                    return [(node['x'], node['C'])]
                return []
            elif op == 'AND':
                satisfying = []
                for child in node['children']:
                    sub = evaluate_node(child)
                    if not sub:
                        return []
                    satisfying.extend(sub)
                return satisfying
            elif op == 'OR':
                for child in node['children']:
                    sub = evaluate_node(child)
                    if sub:
                        return sub
                return []
            return []
            
        sat_leaves = evaluate_node(policy_tree)
        if not sat_leaves:
            return {"satisfied": False, "session_key": ""}
            
        # Perform Lagrange interpolation over satisfying leaves
        # K_master = sum( C_i * L_i ) mod p
        xs = [x for x, c in sat_leaves]
        cs = [c for x, c in sat_leaves]
        
        K_master = 0
        for i in range(len(sat_leaves)):
            xi, ci = sat_leaves[i]
            num = 1
            den = 1
            for j in range(len(sat_leaves)):
                if i != j:
                    xj = sat_leaves[j][0]
                    num = (num * (-xj)) % p
                    den = (den * (xi - xj)) % p
            Li = (num * pow(den, p - 2, p)) % p
            K_master = (K_master + ci * Li) % p
            
        session_key = hashlib.sha256(str(K_master).encode()).hexdigest()
        return {"satisfied": True, "session_key": session_key}

if __name__ == "__main__":
    fp = "/tests/abe_data.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task073/tests/abe_data.json"
    evaluator = CPABEEvaluator()
    res = evaluator.decrypt_session_key(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/abe_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
