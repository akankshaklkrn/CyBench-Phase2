# Level 0 Challenge: Kernel eBPF Static Safety & Bounds Verifier (`ebpf_security_verifier_l0`)

You are tasked with implementing a **Static eBPF Bytecode Safety & Bounds Verifier Engine** inside a simulated operating system kernel environment. Kernel eBPF verifiers protect ring 0 execution by performing abstract interpretation across bytecode instructions prior to JIT compilation. Any bug in the verifier allowing out-of-bounds pointer arithmetic, uninitialized stack reads, map value overflow, or pointer leaks enables arbitrary kernel memory read/write exploits.

## System Specification

The verifier simulates abstract states (`bpf_verifier_state_t`) for the 11 BPF registers (`r0` through `r10`) across bytecode instructions (`bpf_insn_t`).

### 1. Bytecode & State Structures

```c
#define BPF_MAX_REG 11
#define BPF_MAX_INSNS 64

typedef enum {
    BPF_REG_NOT_INIT = 0,
    BPF_REG_SCALAR = 1,
    BPF_REG_PTR_TO_CTX = 2,
    BPF_REG_PTR_TO_MAP_VALUE = 3,
    BPF_REG_PTR_TO_STACK = 4
} bpf_reg_type_t;

typedef struct {
    bpf_reg_type_t type;
    int64_t smin_val;
    int64_t smax_val;
    uint32_t map_value_size;
    int64_t ptr_offset;
} bpf_reg_state_t;

typedef struct {
    bpf_reg_state_t regs[BPF_MAX_REG];
    uint8_t stack_init[512]; // 1 if initialized, 0 if uninitialized
} bpf_verifier_state_t;

typedef enum {
    BPF_OP_MOV = 0,      // r_dst = r_src or imm
    BPF_OP_ADD = 1,      // r_dst += r_src or imm
    BPF_OP_SUB = 2,      // r_dst -= r_src or imm
    BPF_OP_LDX = 3,      // r_dst = *(uint64_t*)(r_src + off)
    BPF_OP_STX = 4,      // *(uint64_t*)(r_dst + off) = r_src
    BPF_OP_JEQ = 5,      // if r_dst == imm jump off
    BPF_OP_JGT = 6,      // if r_dst > imm jump off
    BPF_OP_EXIT = 7      // return r0
} bpf_opcode_t;

typedef struct {
    bpf_opcode_t opcode;
    uint8_t dst_reg;
    uint8_t src_reg;
    int16_t off;
    int64_t imm;
    uint32_t map_size_meta; // Used for MOV when setting MAP_VALUE ptr
} bpf_insn_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void bpf_init_state(bpf_verifier_state_t *st)`
Initializes the verifier abstract state at entry (`pc = 0`):
- All registers `0` through `9` initialized with `type = BPF_REG_NOT_INIT`, `smin_val = 0`, `smax_val = 0`, `map_value_size = 0`, `ptr_offset = 0`.
- Register `r1` (context pointer passed to eBPF program) initialized to `type = BPF_REG_PTR_TO_CTX`, `ptr_offset = 0`, `smin_val = 0`, `smax_val = 0`.
- Register `r10` (read-only frame pointer) initialized to `type = BPF_REG_PTR_TO_STACK`, `ptr_offset = 0`, `smin_val = 0`, `smax_val = 0`.
- Clear `stack_init[0..511]` to `0`.

#### `int bpf_check_reg_read(const bpf_verifier_state_t *st, uint8_t regno)`
Verifies that register `regno` (`0` to `10`) is safe to read:
- Must check that `regno < BPF_MAX_REG` and `st->regs[regno].type != BPF_REG_NOT_INIT`.
- Return `0` if safe, `-1` (`BPF_ERR_UNINIT_REG`) if unsafe.

#### `int bpf_verify_alu(bpf_verifier_state_t *st, const bpf_insn_t *insn)`
Verifies and simulates arithmetic operations (`BPF_OP_MOV`, `BPF_OP_ADD`, `BPF_OP_SUB`):
- Must enforce `insn->dst_reg < BPF_MAX_REG` and `insn->dst_reg != 10` (cannot overwrite read-only stack pointer `r10`).
- If `insn->src_reg < BPF_MAX_REG`, verify source via `bpf_check_reg_read(st, insn->src_reg)`.
- **`BPF_OP_MOV`**:
  - If `insn->src_reg < BPF_MAX_REG`: copy exact state (`st->regs[insn->dst_reg] = st->regs[insn->src_reg]`).
  - If `insn->src_reg == 255` (immediate mode): set `dst_reg.type = BPF_REG_SCALAR`, `smin_val = smax_val = insn->imm`, `ptr_offset = 0`.
  - If `insn->src_reg == 254` (simulated map lookup return imm): set `dst_reg.type = BPF_REG_PTR_TO_MAP_VALUE`, `map_value_size = insn->map_size_meta`, `ptr_offset = insn->imm`, `smin_val = smax_val = 0`.
- **`BPF_OP_ADD` / `BPF_OP_SUB`**:
  - If `dst` is `BPF_REG_PTR_TO_MAP_VALUE` or `BPF_REG_PTR_TO_STACK`:
    - Adding/subtracting two pointers MUST be rejected (return `-2`).
    - Adding a `BPF_REG_SCALAR` or immediate `imm` to a pointer modifies `dst.ptr_offset` (`+=` or `-=`).
    - For `BPF_REG_PTR_TO_MAP_VALUE`, if the resulting `ptr_offset < 0` or `ptr_offset >= (int64_t)dst.map_value_size`, return `-3` (`BPF_ERR_OUT_OF_BOUNDS`).
  - If `dst` is `BPF_REG_SCALAR`:
    - Adding/subtracting a pointer to/from a scalar is forbidden (return `-2`).
    - Scalar arithmetic updates `smin_val` and `smax_val` by adding/subtracting operand values.
  - Return `0` if safe.

#### `int bpf_verify_mem(bpf_verifier_state_t *st, const bpf_insn_t *insn)`
Verifies memory loads (`BPF_OP_LDX`) and stores (`BPF_OP_STX`):
- **`BPF_OP_LDX`** (`r_dst = *(uint64_t*)(r_src + off)`):
  - Verify `insn->dst_reg < 10` and `bpf_check_reg_read(st, insn->src_reg) == 0`.
  - If `src` is `BPF_REG_PTR_TO_MAP_VALUE` or `BPF_REG_PTR_TO_CTX`:
    - Effective offset `e_off = st->regs[insn->src_reg].ptr_offset + insn->off`.
    - If `src` is `BPF_REG_PTR_TO_MAP_VALUE`: check `e_off < 0` or `e_off + 8 > (int64_t)st->regs[insn->src_reg].map_value_size`. If out of bounds -> return `-3`.
    - If `src` is `BPF_REG_PTR_TO_CTX`: check `e_off < 0` or `e_off + 8 > 64`. If out of bounds -> return `-3`.
    - Upon success, set `dst` to `BPF_REG_SCALAR` (`smin_val = smax_val = 0`).
  - If `src` is `BPF_REG_PTR_TO_STACK`:
    - Effective offset `e_off = st->regs[insn->src_reg].ptr_offset + insn->off`.
    - Stack bounds check: `e_off < -512` or `e_off + 8 > 0`. If out of bounds -> return `-3`.
    - Initialization check: every byte in `stack_init[512 + e_off .. 512 + e_off + 7]` MUST be `1`. If any byte is `0` -> return `-4` (`BPF_ERR_UNINIT_STACK`).
    - Set `dst` to `BPF_REG_SCALAR`.
  - If `src` is `BPF_REG_SCALAR` or `NOT_INIT` -> return `-5` (`BPF_ERR_INVALID_MEM`).
- **`BPF_OP_STX`** (`*(uint64_t*)(r_dst + off) = r_src`):
  - Verify `bpf_check_reg_read(st, insn->dst_reg) == 0` and `bpf_check_reg_read(st, insn->src_reg) == 0`.
  - If `dst` is `BPF_REG_PTR_TO_MAP_VALUE` or `BPF_REG_PTR_TO_CTX`:
    - Same bounds checks as LDX. If out of bounds -> return `-3`.
    - If storing a pointer (`src` is not `BPF_REG_SCALAR`) into `CTX` or `MAP_VALUE`, return `-6` (`BPF_ERR_PTR_LEAK`).
  - If `dst` is `BPF_REG_PTR_TO_STACK`:
    - Stack bounds check: `e_off < -512` or `e_off + 8 > 0` -> return `-3`.
    - Mark stack bytes initialized: `stack_init[512 + e_off .. 512 + e_off + 7] = 1`.
  - If `dst` is `BPF_REG_SCALAR` -> return `-5`.
- Return `0` on success.

#### `int bpf_verify_prog(const bpf_insn_t *insns, int num_insns)`
Verifies an entire eBPF program by simulating instruction execution linearly up to `num_insns`:
- Initialize state via `bpf_init_state(&st)`.
- Loop `pc = 0` to `num_insns - 1`:
  - If `pc < 0` or `pc >= num_insns` -> return `-7` (`BPF_ERR_INVALID_PC`).
  - Depending on `insns[pc].opcode`:
    - `BPF_OP_MOV`, `BPF_OP_ADD`, `BPF_OP_SUB`: call `bpf_verify_alu(&st, &insns[pc])`. If `< 0`, return error code.
    - `BPF_OP_LDX`, `BPF_OP_STX`: call `bpf_verify_mem(&st, &insns[pc])`. If `< 0`, return error code.
    - `BPF_OP_JEQ`, `BPF_OP_JGT`: verify `bpf_check_reg_read(&st, insns[pc].dst_reg) == 0`. Check target `target_pc = pc + 1 + insns[pc].off`. If `target_pc < 0` or `target_pc >= num_insns` -> return `-7`. (Linear verification check: verify instruction is valid).
    - `BPF_OP_EXIT`: verify `bpf_check_reg_read(&st, 0) == 0` (return register `r0` must be initialized). If `st.regs[0].type != BPF_REG_SCALAR`, return `-8` (`BPF_ERR_RET_PTR`). Return `0` (Program successfully verified!).
- If loop terminates without encountering `BPF_OP_EXIT`, return `-9` (`BPF_ERR_NO_EXIT`).

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) simulating 8 strict kernel security scenarios:
1. Valid Program: Stack spill/fill, map lookup pointer dereference, scalar return `r0`.
2. Uninitialized Register Read Trapping (`r3` read before initialization).
3. Out-of-Bounds Map Value Access (`r_map + 48` when map size is `32`).
4. Stack Out-of-Bounds & Uninitialized Stack Read Trapping (`fp - 520` load/store).
5. Pointer Leak Prevention (`STX` storing `BPF_REG_PTR_TO_STACK` into map memory).
6. Invalid Pointer Arithmetic (`ADD` two pointer registers together).
7. Invalid Return Register Type (returning map pointer in `r0` instead of scalar).
8. Branch Target Validation & Missing Exit Instruction Check.

If your verifier accurately traps all malicious payloads and passes safe programs without memory issues, the driver outputs:
```
cyberbench{ebpf_security_verifier_state_<64-bit-hex-hash>}
```
