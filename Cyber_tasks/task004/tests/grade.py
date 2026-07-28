import os
import sys
import csv

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

def grade():
    try:
        if not os.path.exists("/src/solution.py"):
            write_reward(0.0, "FAIL: /src/solution.py not found.")
            return

        # Check for forbidden imports
        with open("/src/solution.py", "r") as f:
            code = f.read()
        forbidden = ['cryptography', 'pycryptodome', 'Crypto.Cipher', 'from Crypto', 'import Crypto', 'hashlib', 'hmac']
        for lib in forbidden:
            if lib in code:
                write_reward(0.0, f"FAIL: Forbidden import detected: {lib}")
                return

        # Run the solution
        results_file = "/src/results.csv"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/results.csv not found.")
            return

        # Load test vectors
        vectors_path = "/tests/test_vectors.csv"
        if not os.path.exists(vectors_path):
            vectors_path = "/Users/jatinjena/Downloads/tasknew/task067/tests/test_vectors.csv"

        expected = {}
        with open(vectors_path, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                key = (row["plaintext"], row["key"])
                expected[key] = row["expected_ciphertext"]

        # Load results
        correct = 0
        total = 0
        first_fail = None
        with open(results_file, "r") as f:
            reader = csv.DictReader(f)
            for row in reader:
                total += 1
                key = (row["plaintext"], row["key"])
                if key in expected:
                    if row["ciphertext"] == expected[key]:
                        correct += 1
                    elif first_fail is None:
                        first_fail = f"pt={row['plaintext']}, expected={expected[key]}, got={row['ciphertext']}"

        if correct == len(expected) and total == len(expected):
            write_reward(1.0, f"PASS: All {correct}/{total} test vectors match.")
        else:
            msg = f"FAIL: {correct}/{len(expected)} correct."
            if first_fail:
                msg += f" First mismatch: {first_fail}"
            write_reward(0.0, msg)

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
