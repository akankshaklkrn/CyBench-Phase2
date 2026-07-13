import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Queue Bench...")
build = subprocess.run(["gcc", "-O3", "-Wall", "-Werror", "-pthread", "-o", "/out/queue_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Queue Tests...")
run = subprocess.run(["/out/queue_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Queue Success!" in run.stdout:
    write_reward(1.0, "PASS: Queue implemented successfully")
else:
    write_reward(0.0, "FAIL: Queue crashed or deadlocked")
