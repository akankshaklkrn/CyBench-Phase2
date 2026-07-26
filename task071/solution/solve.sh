#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os

class BerlekampWelchSolver:
    def recover_secret(self, filepath: str) -> int:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        p = data['prime']
        k = data['k']
        E = data['E']
        shares = data['shares']
        
        num_unknowns = (k + E) + E # Q coeffs (0..k+E-1) + E coeffs (0..E-1)
        matrix = []
        
        # Build system Q(xi) - yi * E(xi) = 0 (mod p)
        # Q(x) = q_{k+E-1} x^{k+E-1} + ... + q_0
        # E(x) = x^E + e_{E-1} x^{E-1} + ... + e_0
        # Equation: q_0 + q_1 xi + ... + q_{k+E-1} xi^{k+E-1} - yi e_0 - yi e_1 xi ... = yi xi^E (mod p)
        
        for x_i, y_i in shares:
            row = []
            # Coefficients of Q(x)
            for deg in range(k + E):
                row.append(pow(x_i, deg, p))
            # Coefficients of E(x) (0..E-1)
            for deg in range(E):
                row.append((-y_i * pow(x_i, deg, p)) % p)
            # RHS: y_i * x_i^E
            rhs = (y_i * pow(x_i, E, p)) % p
            row.append(rhs)
            matrix.append(row)
            
        # Gaussian Elimination over F_p
        num_rows = len(matrix)
        num_cols = num_unknowns
        
        for col in range(num_cols):
            pivot = -1
            for r in range(col, num_rows):
                if matrix[r][col] % p != 0:
                    pivot = r
                    break
            if pivot == -1:
                continue
            matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
            
            inv = pow(matrix[col][col], p - 2, p)
            for c in range(col, num_cols + 1):
                matrix[col][c] = (matrix[col][c] * inv) % p
                
            for r in range(num_rows):
                if r != col and matrix[r][col] != 0:
                    factor = matrix[r][col]
                    for c in range(col, num_cols + 1):
                        matrix[r][c] = (matrix[r][c] - factor * matrix[col][c]) % p
                        
        q0 = matrix[0][num_cols] % p
        e0 = matrix[k + E][num_cols] % p if E > 0 else 1
        
        # Secret S = q0 / e0 (mod p)
        if e0 == 0:
            return q0
        return (q0 * pow(e0, p - 2, p)) % p

if __name__ == "__main__":
    fp = "/tests/shares.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task071/tests/shares.json"
    solver = BerlekampWelchSolver()
    secret = solver.recover_secret(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/threshold_result.json", "w") as f:
        json.dump({"secret": secret}, f, indent=2)
PYEOF
cd /src && python3 solution.py
