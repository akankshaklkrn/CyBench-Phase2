# Task 083: Seccomp-BPF Syscall Filter Bytecode Evaluator

You are a Linux kernel security engineer building a **Seccomp-BPF Bytecode Emulator and Syscall Auditor**.

## Seccomp-BPF Bytecode Execution Model

Linux Seccomp-BPF filters consist of a sequence of 8-byte BPF instructions (`sock_filter` struct):
- `code` (2 bytes, uint16 little-endian): Opcode (e.g. `BPF_LD`, `BPF_JEQ`, `BPF_RET`).
- `jt` (1 byte, uint8): Jump offset if true.
- `jf` (1 byte, uint8): Jump offset if false.
- `k` (4 bytes, uint32 little-endian): Immediate value / offset into `seccomp_data`.

### Seccomp Data Structure (`seccomp_data`):
- Offset 0 (`0x00`): `nr` (uint32) — Syscall number (e.g. `60` for `sys_exit`, `59` for `sys_execve`).
- Offset 4 (`0x04`): `arch` (uint32) — Architecture ID (e.g. `0xC000003E` for `AUDIT_ARCH_X86_64`).

### Execution & Jump Logic:
- Program starts at instruction index 0. Accumulator $A = 0$.
- `BPF_LD | BPF_W | BPF_ABS` (`code = 0x20`): Load 32-bit word from `seccomp_data` offset $k$ into $A$.
- `BPF_JMP | BPF_JEQ | BPF_K` (`code = 0x15`): If $A == k$, jump pc $+ 1 + jt$, else jump pc $+ 1 + jf$.
- `BPF_RET | BPF_K` (`code = 0x06`): Terminate filter with return action $k$.
  - Action `0x7FFF0000`: `SECCOMP_RET_ALLOW` (Syscall allowed).
  - Action `0x00000000`: `SECCOMP_RET_KILL_PROCESS` (Syscall denied & process killed).

## Input Schema (`tests/seccomp_policy.json`)

```json
{
  "bpf_bytecode": "2000000004000000150000013e0000c006000000000000002000000000000000150001003b000000060000000000ff7f0600000000000000",
  "syscall_evaluations": [
    {"syscall_nr": 59, "arch": 3221225534},
    {"syscall_nr": 60, "arch": 3221225534}
  ]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `SeccompEvaluator`:
```python
class SeccompEvaluator:
    def evaluate_policy(self, filepath: str) -> dict:
        # filepath: path to seccomp_policy.json
        # returns: dict {"audit_results": [{"syscall_nr": int, "action": "ALLOW" or "KILL"}, ...]}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/seccomp_result.json`.

## Rules & Constraints
- **Python Standard Library Only** (`struct`, `json`, `os`, `sys`).
- Dynamic relative path resolution MUST be used for output.
