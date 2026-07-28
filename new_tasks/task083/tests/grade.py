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

        results_file = "/src/seccomp_result.json"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/seccomp_result.json not found.")
            return

        exp_file = "/tests/expected_seccomp_result.json"
        if not os.path.exists(exp_file):
            exp_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "expected_seccomp_result.json")

        with open(exp_file, "r") as f:
            expected = json.load(f)

        with open(results_file, "r") as f:
            actual = json.load(f)

        if actual.get("audit_results") == expected.get("audit_results"):
            write_reward(1.0, f"PASS: Seccomp BPF policy audited successfully: {actual.get('audit_results')}")
        else:
            write_reward(0.0, f"FAIL: Seccomp audit failed. Expected {expected}, got {actual}")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
