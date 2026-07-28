import os
import subprocess
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

        results_file = "/src/oauth_result.json"
        # Never trust output left behind by an agent self-test. Run the submitted
        # solution against the authoritative input mounted at /tests.
        if os.path.exists(results_file):
            os.remove(results_file)

        try:
            completed = subprocess.run(
                [sys.executable, "solution.py"],
                cwd="/src",
                capture_output=True,
                text=True,
                timeout=60,
            )
        except subprocess.TimeoutExpired:
            write_reward(0.0, "FAIL: solution.py timed out after 60 seconds")
            return

        if completed.returncode != 0:
            stderr = completed.stderr.strip()
            reason = f"FAIL: solution.py exited with code {completed.returncode}"
            if stderr:
                reason += f": {stderr[-500:]}"
            write_reward(0.0, reason)
            return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/oauth_result.json not found.")
            return

        exp_file = "/tests/expected_oauth_result.json"
        if not os.path.exists(exp_file):
            exp_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), "expected_oauth_result.json")

        with open(exp_file, "r") as f:
            expected = json.load(f)

        with open(results_file, "r") as f:
            actual = json.load(f)

        if (actual.get("valid") == expected.get("valid") and
            actual.get("error") == expected.get("error")):
            write_reward(1.0, f"PASS: OAuth 2.0 PKCE flow verified: valid={actual.get('valid')}")
        else:
            write_reward(0.0, f"FAIL: OAuth PKCE verification failed. Expected {expected}, got {actual}")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
