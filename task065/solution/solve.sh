#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class R1CSVerifier:
    def solve_and_verify(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = int(data['prime'])
        num_vars = data['num_variables']
        num_constraints = data['num_constraints']
        
        w = [None] * num_vars
        for k, v in data['partial_witness'].items():
            w[int(k)] = int(v) % p
            
        # Parse sparse matrices
        A_raw = data['A']
        B_raw = data['B']
        C_raw = data['C']
        
        # Iteratively solve for unassigned variables in witness
        changed = True
        while changed:
            changed = False
            for row in range(num_constraints):
                # Calculate row combinations
                a_terms = [x for x in A_raw if x[0] == row]
                b_terms = [x for x in B_raw if x[0] == row]
                c_terms = [x for x in C_raw if x[0] == row]
                
                # Check if A * B = C can uniquely resolve an unknown variable
                # In our circuit construction, every C term defines the target var
                if len(c_terms) == 1:
                    target_var = c_terms[0][1]
                    c_coeff = int(c_terms[0][2])
                    if w[target_var] is None:
                        # Check if all A and B terms are known
                        a_known = all(w[var] is not None for _, var, _ in a_terms)
                        b_known = all(w[var] is not None for _, var, _ in b_terms)
                        if a_known and b_known:
                            val_a = sum((int(coeff) * w[var]) for _, var, coeff in a_terms) % p
                            val_b = sum((int(coeff) * w[var]) for _, var, coeff in b_terms) % p
                            prod = (val_a * val_b) % p
                            # Solve c_coeff * target_var = prod (mod p)
                            inv_c = pow(c_coeff, p - 2, p)
                            w[target_var] = (prod * inv_c) % p
                            changed = True
                            
        # Final verification: check (A*w) * (B*w) == C*w (mod p) for all rows
        for row in range(num_constraints):
            a_terms = [x for x in A_raw if x[0] == row]
            b_terms = [x for x in B_raw if x[0] == row]
            c_terms = [x for x in C_raw if x[0] == row]
            
            val_a = sum((int(coeff) * w[var]) for _, var, coeff in a_terms) % p
            val_b = sum((int(coeff) * w[var]) for _, var, coeff in b_terms) % p
            val_c = sum((int(coeff) * w[var]) for _, var, coeff in c_terms) % p
            
            if (val_a * val_b) % p != val_c:
                return {"valid": False, "full_witness": []}
                
        return {"valid": True, "full_witness": [str(x) for x in w]}

if __name__ == "__main__":
    fp = "/tests/r1cs_circuit.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task065/tests/r1cs_circuit.json"
    verifier = R1CSVerifier()
    res = verifier.solve_and_verify(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/r1cs_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
