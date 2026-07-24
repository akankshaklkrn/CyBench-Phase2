import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Buddy Memory Allocator Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-fsanitize=address,undefined", "-o", "/out/buddy_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Buddy Memory Allocator Coalescing Tests...")
run = subprocess.run(["/out/buddy_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Buddy Memory Allocator Recursive Coalescing Success!" in run.stdout:
    write_reward(1.0, "PASS: Buddy allocator correctly performed block splitting and bitwise recursive coalescing")
else:
    write_reward(0.0, "FAIL: Buddy allocator fragmented memory, failed coalescing, or crashed under AddressSanitizer/UBSAN")
