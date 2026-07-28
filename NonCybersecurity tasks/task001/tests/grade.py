import subprocess
import sys
import re
import os

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))
    with open("/src/debug.log", "w") as f:
        f.write(f"Reward: {reward}\nReason: {reason}\n")

def grade():
    try:
        with open("/src/solution.cpp", "r") as f:
            code = f.read()
            
        banned_terms = ["mutex", "lock_guard", "unique_lock", "atomic_flag", "spinlock", "spin_lock", "yield"]
        for term in banned_terms:
            if re.search(r'\b' + term + r'\b', code, re.IGNORECASE):
                write_reward(0.0, f"FAIL: Banned term '{term}' found")
                return

        # Compile
        compile_result = subprocess.run(
            ["g++", "-O3", "-pthread", "-std=c++17", "-latomic", "-o", "/src/test_stack", "/tests/main.cpp"],
            capture_output=True, text=True
        )
        if compile_result.returncode != 0:
            write_reward(0.0, "FAIL: Compilation failed. " + compile_result.stderr)
            return
            
        # Run
        run_result = subprocess.run(
            ["/src/test_stack"],
            capture_output=True, text=True, timeout=10
        )
        
        if "SUCCESS" in run_result.stdout:
            write_reward(1.0, "PASS: Lock-free stack implemented and Aba test passed.")
        else:
            write_reward(0.0, "FAIL: ABA problem detected or state mismatch.")
            
    except Exception as e:
        write_reward(0.0, "FAIL: Exception occurred: " + str(e))

if __name__ == "__main__":
    grade()
