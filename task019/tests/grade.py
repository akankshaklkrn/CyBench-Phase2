import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Skip List Bench...")
build = subprocess.run(["gcc", "-O3", "-Wall", "-Werror", "-pthread", "-o", "/out/skiplist_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Skip List Tests...")
run = subprocess.run(["/out/skiplist_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Skip List Success!" in run.stdout:
    write_reward(1.0, "PASS: Skip List implemented successfully")
else:
    write_reward(0.0, "FAIL: Skip List crashed, deadlocked, or corrupted level pointers")
