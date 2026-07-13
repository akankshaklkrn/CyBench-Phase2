import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Ring Buffer TSAN Bench...")
build = subprocess.run(["gcc", "-O3", "-Wall", "-Werror", "-pthread", "-fsanitize=thread,undefined", "-o", "/out/ring_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Ring Buffer TSAN Tests...")
run = subprocess.run(["/out/ring_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Ring Buffer TSAN Success!" in run.stdout:
    write_reward(1.0, "PASS: Ring buffer implemented lock-free without data races")
else:
    write_reward(0.0, "FAIL: Ring buffer crashed, deadlocked, or triggered TSAN/UBSAN data race errors")
