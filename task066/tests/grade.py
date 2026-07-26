import os
import sys

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

        results_file = "/src/recovered_dpa_key.txt"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/recovered_dpa_key.txt not found.")
            return

        exp_file = "/tests/expected_key.txt"
        if not os.path.exists(exp_file):
            exp_file = "/Users/jatinjena/Downloads/tasknew/task066/tests/expected_key.txt"

        with open(exp_file, "r") as f:
            expected = f.read().strip().lower()

        with open(results_file, "r") as f:
            actual = f.read().strip().lower()

        if actual == expected:
            write_reward(1.0, f"PASS: DPA recovered exact 16-byte AES key: {actual}")
        else:
            write_reward(0.0, f"FAIL: Key mismatch. Got {actual}, expected {expected}")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
