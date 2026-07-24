import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling RB-Tree Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-o", "/out/rbtree_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running RB-Tree Tests...")
run = subprocess.run(["/out/rbtree_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: RB-Tree Success!" in run.stdout:
    write_reward(1.0, "PASS: RB-Tree implemented successfully")
else:
    write_reward(0.0, "FAIL: RB-Tree crashed or failed invariant verification")
