import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Raft Consensus Engine Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-fsanitize=address", "-o", "/out/raft_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Raft Consensus Cluster Tests...")
run = subprocess.run(["/out/raft_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Raft Consensus Cluster Synchronization Success!" in run.stdout:
    write_reward(1.0, "PASS: Raft consensus state machine correctly handled elections and split-brain log replication")
else:
    write_reward(0.0, "FAIL: Raft consensus engine diverged or failed under AddressSanitizer")
