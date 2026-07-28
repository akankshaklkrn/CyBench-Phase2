import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling WAL Crash Recovery Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-fsanitize=address", "-o", "/out/wal_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running WAL Crash Recovery Tests...")
run = subprocess.run(["/out/wal_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: WAL Crash Recovery Success!" in run.stdout:
    write_reward(1.0, "PASS: ARIES recovery engine correctly analyzed, redid, and undid transactions")
else:
    write_reward(0.0, "FAIL: Recovery engine failed ACID consistency bounds or crashed under ASAN")
