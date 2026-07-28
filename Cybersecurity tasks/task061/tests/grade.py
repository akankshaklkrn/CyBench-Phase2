import os
import sys

REWARD_FILE = "/logs/verifier/reward.txt"
EXPECTED_KEY = "deadbeefcafebabe"

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

        results_file = "/src/recovered_key.txt"
        if not os.path.exists(results_file):
            exit_code = os.system("cd /src && timeout 60 python3 solution.py")
            if exit_code != 0:
                write_reward(0.0, f"FAIL: solution.py exited with code {exit_code}")
                return

        if not os.path.exists(results_file):
            write_reward(0.0, "FAIL: /src/recovered_key.txt not found.")
            return

        with open(results_file, "r") as f:
            recovered = f.read().strip().lower()

        if recovered == EXPECTED_KEY:
            write_reward(1.0, f"PASS: Recovered key {recovered} matches expected.")
        else:
            # Count correct bits
            try:
                rec_int = int(recovered, 16)
                exp_int = int(EXPECTED_KEY, 16)
                xor = rec_int ^ exp_int
                wrong_bits = bin(xor).count('1')
                write_reward(0.0, f"FAIL: Key mismatch. Got {recovered}, expected {EXPECTED_KEY}. {wrong_bits}/64 bits wrong.")
            except:
                write_reward(0.0, f"FAIL: Key mismatch. Got '{recovered}', expected '{EXPECTED_KEY}'.")

    except Exception as e:
        write_reward(0.0, f"FAIL: Exception: {e}")

if __name__ == "__main__":
    grade()
