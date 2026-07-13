import os
import sys
import subprocess

REWARD_FILE = "/logs/verifier/reward.txt"

def write_reward(reward, reason):
    print("Reward: " + str(reward) + " - " + reason)
    os.makedirs("/logs/verifier", exist_ok=True)
    with open(REWARD_FILE, "w") as f:
        f.write(str(reward))

print("Compiling x86-64 Mini-JIT Bytecode Compiler Bench...")
build = subprocess.run(["gcc", "-O2", "-Wall", "-Werror", "-fsanitize=address", "-o", "/out/jit_bench", "/src/target.c"], capture_output=True)
if build.returncode != 0:
    write_reward(0.0, "FAIL: Compilation failed")
    sys.exit(0)

print("Running x86-64 Mini-JIT Compiler Tests...")
run = subprocess.run(["/out/jit_bench"], capture_output=True, text=True)
if run.returncode == 0 and "FLAG: x86-64 Mini-JIT Compilation Success!" in run.stdout:
    write_reward(1.0, "PASS: Mini-JIT compiler correctly translated bytecode into executable x86-64 machine code")
else:
    write_reward(0.0, "FAIL: JIT compiler failed execution or crashed under AddressSanitizer")
