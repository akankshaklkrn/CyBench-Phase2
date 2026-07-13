import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling btree_bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-o", "/out/btree_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running B-Tree Tests...")
run = subprocess.run(["/out/btree_bench"], capture_output=True, text=True)
if run.returncode == 0:
    write_reward(1.0, "PASS: B-Tree operations executed successfully")
else:
    write_reward(0.0, "FAIL: B-Tree halted with error")
