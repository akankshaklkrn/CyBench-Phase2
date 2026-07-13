# Challenge: User-Space eBPF Static Verifier & Execution Engine (`ebpf_verifier_engine_l0`)

You are tasked with implementing a user-space **eBPF Static Bytecode Verifier and Abstract Execution Engine** in standard C under AddressSanitizer (`-fsanitize=address,undefined`).

## Technical Specifications

### 1. eBPF Instruction Set Architecture
- **Registers**: 11 64-bit registers (`R0..R10`).
  - `R0`: Return value register.
  - `R1`: Pointer to context buffer (`ctx`) upon entry.
  - `R10`: Read-only frame pointer pointing to the top of a 512-byte stack (`[R10 - 512, R10)`).
- **Opcodes**:
  - `BPF_MOV_IMM` (0x01): `r[dst] = imm`
  - `BPF_MOV_REG` (0x02): `r[dst] = r[src]`
  - `BPF_ADD_IMM` (0x03): `r[dst] += imm`
  - `BPF_ADD_REG` (0x04): `r[dst] += r[src]`
  - `BPF_SUB_IMM` (0x05): `r[dst] -= imm`
  - `BPF_SUB_REG` (0x06): `r[dst] -= r[src]`
  - `BPF_MUL_IMM` (0x07): `r[dst] *= imm`
  - `BPF_MUL_REG` (0x08): `r[dst] *= r[src]`
  - `BPF_DIV_IMM` (0x09): `r[dst] /= imm` (Divisor must not be 0)
  - `BPF_DIV_REG` (0x0A): `r[dst] /= r[src]` (Divisor must not be 0)
  - `BPF_LDX_MEM` (0x10): `r[dst] = *(uint64_t*)(r[src] + off)`
  - `BPF_STX_MEM` (0x20): `*(uint64_t*)(r[dst] + off) = r[src]`
  - `BPF_JEQ_IMM` (0x30): `if (r[dst] == imm) pc += off`
  - `BPF_JGT_IMM` (0x31): `if (r[dst] > imm) pc += off`
  - `BPF_JMP_A`   (0x40): `pc += off`
  - `BPF_EXIT`    (0x99): Terminate execution and return `R0`.

### 2. Static Verifier Safety Rules (`ebpf_verify_program`)
- Before executing any bytecode, `ebpf_verify_program` must perform static analysis / abstract interpretation:
  1. **Jump Safety**: Every jump target (`pc + 1 + off`) must fall within valid program bounds (`0 <= target < num_insns`).
  2. **Register Initialization**: Any source register (`src_reg` or `dst_reg` used as read source) must be initialized (`REG_SCALAR`, `REG_PTR_CTX`, or `REG_PTR_STACK`). Reading `REG_NOT_INIT` must be rejected.
  3. **Division by Zero**: `BPF_DIV_IMM` with `imm == 0` or `BPF_DIV_REG` where `r[src]` can be 0 must be rejected.
  4. **Memory Safety**:
     - `BPF_LDX_MEM` / `BPF_STX_MEM` on `REG_PTR_STACK` (`R10`) must satisfy `-512 <= off <= -8` and `off % 8 == 0`.
     - `BPF_LDX_MEM` on `REG_PTR_CTX` (`R11` or `R1`) must satisfy `off >= 0`.
  5. **Termination**: Program must contain at least one reachable `BPF_EXIT`.

### 3. Execution Engine (`ebpf_exec_program`)
- Runs verified bytecode over a 512-byte stack frame (`uint8_t stack[512]`) and context buffer, storing the final `R0` value into `*out_ret`.

## Functions to Implement in `target.c`
```c
bool ebpf_verify_program(const bpf_prog_t *prog, char *err_buf, size_t err_len);
bool ebpf_exec_program(const bpf_prog_t *prog, const uint8_t *ctx, size_t ctx_len, uint64_t *out_ret);
```
