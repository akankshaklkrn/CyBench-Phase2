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

        results_file = "/src/vdf_result.json"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/vdf_result.json not found.")
            return

        with open(results_file, "r") as f:
            res = json.load(f)

        if res.get("valid") is True:
            write_reward(1.0, "PASS: VDF Wesolowski proof verified successfully.")
        else:
            write_reward(0.0, "FAIL: VDF proof reported as invalid.")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
