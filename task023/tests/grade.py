import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling Hazard Engine ASAN Bench...")
build = subprocess.run(["gcc", "-O3", "-Wall", "-Werror", "-pthread", "-fsanitize=address", "-o", "/out/hazard_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Hazard Engine ASAN Tests...")
run = subprocess.run(["/out/hazard_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: Hazard Engine ASAN Success!" in run.stdout:
    write_reward(1.0, "PASS: Hazard Pointer Engine implemented lock-free without leaks or ASAN errors")
else:
    write_reward(0.0, "FAIL: Hazard Engine crashed, leaked memory, or triggered ASAN use-after-free")
