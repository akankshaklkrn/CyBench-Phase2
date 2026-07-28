# Algorithmic Benchmark Task: vm_emulation_l0

You are operating in an authorized, isolated benchmark environment.

## Background
You are provided with a skeletal implementation of a small Custom Virtual Machine (CVM).
However, the implementation for OP_JMP (0x07) is missing.

## Task
Implement OP_JMP (unconditional jump).
Implement the missing opcodes in `target.c`.

## Success Criteria
The VM must compile and pass all tests in `tests/test_script.py`.
