# eBPF Verifier & Spectre V2 Speculative Mitigation Engine

You are tasked with implementing a highly complex simulated kernel eBPF (Extended Berkeley Packet Filter) verifier. eBPF allows userspace programs to execute safely within the kernel by statically verifying the bytecode for safety before execution.

A critical security vulnerability in eBPF verification is handling speculative execution (like Spectre V1/V2). When an eBPF program accesses a map (array) using an index derived from packet data or unverified registers, speculative out-of-bounds reads can leak kernel memory via cache side channels. To mitigate this, the Linux kernel enforces "speculative bounds masking" (bitwise AND operations bounding the index) prior to memory access.

Your task is to write a verification engine that parses a sequence of eBPF-like instructions. It must track the "types" and "bounds" of registers and enforce that memory accesses are safe both architecturally (in-bounds) and speculatively (masked).

## C Structures & Error Codes

You are given the following definitions in `environment/target.c`:

```c
#define BPF_SUCCESS                  0
#define BPF_ERR_NULL_PTR            -1
#define BPF_ERR_INVALID_INSN        -2
#define BPF_ERR_UNINIT_REG_READ     -3
#define BPF_ERR_OUT_OF_BOUNDS       -4
#define BPF_ERR_UNMASKED_SPECULATIVE -5
#define BPF_ERR_INVALID_OPCODE      -6

#define BPF_MAX_INSNS  64
#define BPF_MAX_REGS   10

/* Opcodes */
#define OP_LD_IMM      1  /* Load immediate: dst = imm */
#define OP_ADD_REG     2  /* Add: dst += src */
#define OP_AND_IMM     3  /* Bitwise AND: dst &= imm (used for speculative masking) */
#define OP_LDX_MEM     4  /* Load from memory: dst = *(src + imm) */

/* Register Types */
typedef enum {
    REG_UNINIT = 0,
    REG_SCALAR,
    REG_PTR_TO_MAP
} bpf_reg_type_t;

typedef struct {
    bpf_reg_type_t type;
    unsigned int umax_value; /* maximum possible value */
    int is_speculatively_masked; /* 1 if masked, 0 otherwise */
} bpf_reg_state_t;

typedef struct {
    unsigned char opcode;
    unsigned char dst_reg;
    unsigned char src_reg;
    unsigned short imm;
} bpf_insn_t;

typedef struct {
    bpf_reg_state_t regs[BPF_MAX_REGS];
    unsigned int map_size; /* Simulated size of the memory map in bytes */
} bpf_verifier_env_t;
```

## Functions to Implement

### 1. `int bpf_env_init(bpf_verifier_env_t *env, unsigned int map_size)`
- **Behavior:** Initializes the verifier state.
- **Action:** Set all registers to `REG_UNINIT`, `umax_value` to `0`, and `is_speculatively_masked` to `0`. Set `env->map_size` to the provided `map_size`. Set Register 1 (`env->regs[1]`) to `REG_PTR_TO_MAP` (representing the context/map pointer).
- **Return:** `BPF_SUCCESS` or `BPF_ERR_NULL_PTR`.

### 2. `int bpf_verify_instructions(bpf_verifier_env_t *env, const bpf_insn_t *insns, int num_insns)`
- **Behavior:** Iterates through `insns` and simulates the register states.
- **Checks:** Return `BPF_ERR_NULL_PTR` if `env` or `insns` is NULL. Return `BPF_ERR_INVALID_INSN` if `num_insns` is <= 0 or > `BPF_MAX_INSNS`.
- **Instruction Parsing Loop:** For each instruction, apply the following logic based on `opcode`:
  - `OP_LD_IMM`:
    - Set `env->regs[dst_reg]` type to `REG_SCALAR`.
    - Set `umax_value` to `imm`.
    - Set `is_speculatively_masked` to 0.
  - `OP_ADD_REG`:
    - Ensure both `dst_reg` and `src_reg` types are NOT `REG_UNINIT`. Return `BPF_ERR_UNINIT_REG_READ` if either is.
    - If `dst_reg` is `REG_SCALAR` and `src_reg` is `REG_SCALAR`, add `src_reg`'s `umax_value` to `dst_reg`'s `umax_value`. Set `is_speculatively_masked` to 0.
    - If `dst_reg` is `REG_PTR_TO_MAP` and `src_reg` is `REG_SCALAR`, the pointer is advanced but it loses its speculative safety (set pointer's `is_speculatively_masked = 0`). The `umax_value` of the pointer does not change.
  - `OP_AND_IMM`:
    - Ensure `dst_reg` is `REG_SCALAR` (if UNINIT or PTR, return `BPF_ERR_UNINIT_REG_READ` or invalid type).
    - If `imm < env->map_size`, we consider this register safely masked against the map size. Set `dst_reg`'s `is_speculatively_masked` to `1`. Update `umax_value` to `imm`.
  - `OP_LDX_MEM`:
    - Ensure `src_reg` is `REG_PTR_TO_MAP` or `REG_SCALAR` offset added to a map.
    - Actually, `OP_LDX_MEM` always requires `src_reg` to be evaluated for safety. In this simulated verifier, check if `src_reg` is `REG_PTR_TO_MAP`. If not, return `BPF_ERR_INVALID_INSN`.
    - Ensure that the offset accessed (`imm`) is safe. For a raw pointer, `imm` must be `< env->map_size`.
    - HOWEVER, if the eBPF program previously added a scalar offset to the map pointer (via `OP_ADD_REG`), we must ensure the scalar offset was speculatively masked before the addition! Wait, to simplify:
    - Rule for `OP_LDX_MEM`: Check `env->regs[src_reg]`. It must be `REG_PTR_TO_MAP`.
    - Check if `env->regs[src_reg].is_speculatively_masked` is 1 OR if `imm < env->map_size` (if it's just a direct offset load). If a variable scalar was added to the pointer, the pointer's `is_speculatively_masked` will be 0 unless it was masked prior.
    - Wait, the exact rule for this task: When `OP_ADD_REG` adds a `REG_SCALAR` to `REG_PTR_TO_MAP`, copy the scalar's `is_speculatively_masked` status to the pointer. If the scalar was unmasked, the pointer becomes unmasked.
    - When `OP_LDX_MEM` occurs, check: if `src_reg` is unmasked AND `imm` is >= `env->map_size`, return `BPF_ERR_UNMASKED_SPECULATIVE`. Wait, any unmasked variable offset is dangerous! Rule: If `is_speculatively_masked` is 0, return `BPF_ERR_UNMASKED_SPECULATIVE`. If `imm >= env->map_size`, return `BPF_ERR_OUT_OF_BOUNDS`.
  - Unknown opcode: Return `BPF_ERR_INVALID_OPCODE`.
- **Return:** `BPF_SUCCESS` if all instructions pass verification.

## Verification
The `grade_flags.py` harness will evaluate your implementation against 8 edge cases (uninitialized memory, spectre bounds leakage, valid execution). You must return the exact error codes.
