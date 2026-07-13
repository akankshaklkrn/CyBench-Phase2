import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling CVM...")
# In the actual container, the agent modifies /src/target.c
# We compile it to /out/cvm
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-o", "/out/cvm", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running Bytecode Tests...")
# Dummy bytecode payload that succeeds if the opcodes are implemented properly.
# For this scaffolding, if it runs and exits 0, we pass it.
bytecode = bytearray([0x00]) # HALT
with open("/tmp/test.bin", "wb") as f:
    f.write(bytecode)

run = subprocess.run(["/out/cvm", "/tmp/test.bin"], capture_output=True, text=True)
if run.returncode == 0:
    write_reward(1.0, "PASS: VM executed successfully")
else:
    write_reward(0.0, "FAIL: VM halted with error")
