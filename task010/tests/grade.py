import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Allocator Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-o", "/out/allocator_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Allocator Tests...")
run = subprocess.run(["/out/allocator_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Custom Allocator Success!" in run.stdout:
    write_reward(1.0, "PASS: Custom Allocator implemented successfully")
else:
    write_reward(0.0, "FAIL: Custom Allocator crashed or failed verification")
