import os
import sys
import time

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

def grade():
    try:
        # 1. Check that solution.py exists
        if not os.path.exists("/src/solution.py"):
            write_reward(0.0, "FAIL: /src/solution.py not found.")
            return

        # 2. Check if results.txt already exists (oracle path: solve.sh already ran it)
        results_file = "/src/results.txt"
        if not os.path.exists(results_file):
            # Agent didn't run solution.py yet, so run it now
            start = time.time()
            exit_code = os.system("cd /src && timeout 120 python3 solution.py")
            elapsed = time.time() - start

            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with non-zero code {exit_code} after {elapsed:.1f}s")
                return
        else:
            elapsed = 0.0

        # 3. Check results file exists
        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/results.txt not found after execution.")
            return

        # 4. Load expected answers
        expected_file = "/tests/expected.txt"
        if not os.path.exists(expected_file):
            expected_file = "/Users/jatinjena/Downloads/tasknew/task066/tests/expected.txt"

        with open(expected_file, "r") as f:
            expected = [line.strip() for line in f if line.strip()]

        with open(results_file, "r") as f:
            actual = [line.strip() for line in f if line.strip()]

        # 5. Compare
        if len(actual) != len(expected):
            write_reward(0.0, f"FAIL: Expected {len(expected)} lines, got {len(actual)} lines.")
            return

        mismatches = 0
        first_mismatch = -1
        for i in range(len(expected)):
            if actual[i] != expected[i]:
                mismatches += 1
                if first_mismatch == -1:
                    first_mismatch = i

        if mismatches == 0:
            write_reward(1.0, f"PASS: All {len(expected)} query results correct in {elapsed:.1f}s.")
        else:
            write_reward(0.0, f"FAIL: {mismatches}/{len(expected)} mismatches. First at query {first_mismatch}: expected {expected[first_mismatch]}, got {actual[first_mismatch]}.")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
