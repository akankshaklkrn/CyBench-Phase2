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

        results_file = "/src/rop_payload.bin"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/rop_payload.bin not found.")
            return

        exp_file = "/tests/expected_payload.bin"
        if not os.path.exists(exp_file):
            exp_file = "/Users/jatinjena/Downloads/tasknew/task068/tests/expected_payload.bin"

        with open(exp_file, "rb") as f:
            expected = f.read()

        with open(results_file, "rb") as f:
            actual = f.read()

        if actual == expected:
            write_reward(1.0, f"PASS: ROP chain payload matches exact binary sequence ({len(actual)} bytes).")
        else:
            write_reward(0.0, f"FAIL: Binary mismatch. Expected {len(expected)} bytes, got {len(actual)} bytes.")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
