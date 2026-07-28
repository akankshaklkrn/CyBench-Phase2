import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Concurrent LLRB Tree TSAN Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-pthread", "-o", "/out/llrb_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Concurrent LLRB Tree TSAN Tests...")
run = subprocess.run(["/out/llrb_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: LLRB TSAN Success!" in run.stdout:
    write_reward(1.0, "PASS: Concurrent LLRB Tree implemented without data races")
else:
    write_reward(0.0, "FAIL: LLRB Tree crashed, deadlocked, or violated TSAN data-race safety")
