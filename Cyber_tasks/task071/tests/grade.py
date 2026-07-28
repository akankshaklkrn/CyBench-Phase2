import os
import sys
import json

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

        results_file = "/src/threshold_result.json"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/threshold_result.json not found.")
            return

        exp_file = "/tests/expected_secret.json"
        if not os.path.exists(exp_file):
            exp_file = "/Users/jatinjena/Downloads/tasknew/task071/tests/expected_secret.json"

        with open(exp_file, "r") as f:
            expected = json.load(f)

        with open(results_file, "r") as f:
            actual = json.load(f)

        if actual.get("secret") == expected.get("secret"):
            write_reward(1.0, f"PASS: Berlekamp-Welch secret recovered successfully: {actual.get('secret')}")
        else:
            write_reward(0.0, f"FAIL: Secret mismatch. Expected {expected.get('secret')}, got {actual.get('secret')}")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
