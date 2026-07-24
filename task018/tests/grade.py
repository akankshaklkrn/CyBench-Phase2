import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Radix Tree ASAN Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-fsanitize=address", "-o", "/out/radix_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Radix Tree ASAN Tests...")
run = subprocess.run(["/out/radix_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Radix Tree ASAN Success!" in run.stdout:
    write_reward(1.0, "PASS: Radix Tree ASAN implemented successfully without leaks")
else:
    write_reward(0.0, "FAIL: Radix Tree ASAN crashed, failed parsing, or leaked memory")
