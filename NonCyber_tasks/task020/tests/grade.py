import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Treap Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-o", "/out/treap_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Treap Tests...")
run = subprocess.run(["/out/treap_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Treap Success!" in run.stdout:
    write_reward(1.0, "PASS: Treap dual-invariants implemented successfully")
else:
    write_reward(0.0, "FAIL: Treap crashed or violated BST/Heap invariants")
