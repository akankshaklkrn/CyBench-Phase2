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

        results_file = "/src/classifications.json"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/classifications.json not found.")
            return

        exp_file = "/tests/expected_classifications.json"
        if not os.path.exists(exp_file):
            exp_file = "/Users/jatinjena/Downloads/tasknew/task069/tests/expected_classifications.json"

        with open(exp_file, "r") as f:
            expected = json.load(f)

        with open(results_file, "r") as f:
            actual = json.load(f)

        if len(actual) != len(expected):
            write_reward(0.0, f"FAIL: Expected {len(expected)} session classifications, got {len(actual)}.")
            return

        correct = 0
        first_mismatch = None
        for sess_id, exp_cls in expected.items():
            act_cls = actual.get(sess_id)
            if act_cls == exp_cls:
                correct += 1
            elif first_mismatch is None:
                first_mismatch = f"Session '{sess_id}': expected '{exp_cls}', got '{act_cls}'"

        if correct == len(expected):
            write_reward(1.0, f"PASS: All {len(expected)} sessions correctly classified.")
        else:
            write_reward(0.0, f"FAIL: {correct}/{len(expected)} sessions correct. First mismatch: {first_mismatch}")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
