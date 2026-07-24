# Level 0 Challenge: Sandboxed WebAssembly JIT Security Engine (`sandboxed_wasm_jit_security_l0`)

You are tasked with implementing a **Secure WebAssembly (Wasm) JIT Memory Sandbox & Type-Safety Controller** inside a high-performance virtual machine. WebAssembly runtimes protect host environments by enforcing rigid linear memory boundaries, guard page isolation against heap wrap-around exploits, strict alignment rules, and runtime type-signature checking during indirect table calls (`call_indirect`). Any bug in linear memory translation or signature validation allows JIT escape, host memory corruption, and arbitrary code execution.

## System Specification

The sandbox engine (`wasm_sandbox_t`) manages a 64KB-page linear memory space (`linear_memory`) surrounded by unmapped guard region boundaries, along with an indirect function table (`table_slots`) for dynamic dispatch.

### 1. Sandbox & Instruction Structures

```c
#define WASM_PAGE_SIZE 65536
#define WASM_MAX_PAGES 16
#define WASM_MAX_TABLE_SLOTS 64
#define WASM_GUARD_SIZE 4096

typedef enum {
    PAGE_STATE_UNMAPPED = 0,
    PAGE_STATE_MAPPED = 1,
    PAGE_STATE_GUARD = 2
} page_state_t;

typedef enum {
    WASM_OP_LOAD32 = 1,       // Read 4 bytes from linear memory: *(uint32_t*)(mem + base + offset)
    WASM_OP_STORE32 = 2,      // Write 4 bytes to linear memory: *(uint32_t*)(mem + base + offset) = val
    WASM_OP_LOAD64 = 3,       // Read 8 bytes from linear memory: *(uint64_t*)(mem + base + offset)
    WASM_OP_STORE64 = 4,      // Write 8 bytes to linear memory: *(uint64_t*)(mem + base + offset) = val
    WASM_OP_CALL_INDIRECT = 5 // Invoke table slot: check type signature match
} wasm_opcode_t;

typedef struct {
    wasm_opcode_t opcode;
    uint32_t base_addr;       // Base address operand in linear memory
    uint32_t offset;          // Immediate static offset
    uint64_t value;           // Value for STORE operations or expected type_sig for CALL_INDIRECT
    uint32_t table_idx;       // Index into table_slots for CALL_INDIRECT
} wasm_insn_t;

typedef struct {
    bool is_valid;
    uint64_t type_signature;  // 64-bit hash of function type (params -> returns)
    uint32_t target_code_id;  // Simulated target function identifier
} table_slot_t;

typedef struct {
    uint8_t linear_memory[WASM_MAX_PAGES * WASM_PAGE_SIZE];
    page_state_t page_states[WASM_MAX_PAGES];
    uint32_t current_memory_bytes;
    table_slot_t table_slots[WASM_MAX_TABLE_SLOTS];
    bool is_initialized;
} wasm_sandbox_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void wasm_init_sandbox(wasm_sandbox_t *box, uint32_t initial_pages)`
Initializes the Wasm JIT linear memory sandbox:
- Sets `box->is_initialized = true`.
- If `initial_pages == 0` or `initial_pages > WASM_MAX_PAGES`, cap/clamp `initial_pages` to `1` or `WASM_MAX_PAGES` respectively (must ensure valid bounds `1 .. WASM_MAX_PAGES`).
- Set `box->current_memory_bytes = initial_pages * WASM_PAGE_SIZE`.
- For `i = 0` to `initial_pages - 1`: mark `page_states[i] = PAGE_STATE_MAPPED` and zero out the corresponding bytes in `linear_memory`.
- For `i = initial_pages` to `WASM_MAX_PAGES - 1`: mark `page_states[i] = PAGE_STATE_GUARD`.
- Zero out all `table_slots[0..63]` (`is_valid = false`).

#### `int wasm_register_table_slot(wasm_sandbox_t *box, uint32_t slot_idx, uint64_t type_sig, uint32_t target_id)`
Registers an indirect function target in the dispatch table:
- If `!box || !box->is_initialized || slot_idx >= WASM_MAX_TABLE_SLOTS`, return `-1` (`WASM_ERR_INVALID_SLOT`).
- If `box->table_slots[slot_idx].is_valid`, return `-2` (`WASM_ERR_SLOT_OCCUPIED`).
- Populate `table_slots[slot_idx]` with `is_valid = true`, `type_signature = type_sig`, `target_code_id = target_id`.
- Return `0`.

#### `int wasm_verify_mem_op(const wasm_sandbox_t *box, uint32_t base, uint32_t offset, uint32_t access_size, uint32_t align_mask)`
Verifies linear memory bounds, overflow wrapping, alignment, and guard page isolation before executing a memory instruction:
- If `!box || !box->is_initialized`, return `-1`.
- **Alignment Check**: Check whether `(base + offset) & align_mask != 0`. If misaligned, return `-3` (`WASM_ERR_ALIGNMENT`).
- **32-Bit Integer Overflow & Wrap-Around Check**: Check whether `base + offset < base` (`uint32_t` wrap) or `(base + offset) + access_size < (base + offset)`. If integer wrap-around occurs, immediately return `-4` (`WASM_ERR_OVERFLOW_WRAP`).
- **Linear Memory Bounds Check**: Check whether `(uint64_t)base + offset + access_size > box->current_memory_bytes`.
  - If out of bounds: check which page the target address `(uint64_t)base + offset` falls into (`page_idx = ((uint64_t)base + offset) / WASM_PAGE_SIZE`).
  - If `page_idx < WASM_MAX_PAGES && box->page_states[page_idx] == PAGE_STATE_GUARD`, return `-5` (`WASM_ERR_GUARD_PAGE_HIT`).
  - Otherwise, return `-6` (`WASM_ERR_OUT_OF_BOUNDS`).
- Return `0` if memory access is completely safe within mapped linear memory.

#### `int wasm_execute_instruction(wasm_sandbox_t *box, const wasm_insn_t *insn, uint64_t *out_result)`
Executes a single sandboxed Wasm instruction inside the virtual machine:
- If `!box || !insn || !out_result`, return `-1`.
- **`WASM_OP_LOAD32`** (`access_size = 4, align_mask = 3`):
  - Call `wasm_verify_mem_op(box, insn->base_addr, insn->offset, 4, 3)`. If `< 0`, return that error code.
  - Read `uint32_t` from `linear_memory + insn->base_addr + insn->offset` (little-endian/host), store zero-extended into `*out_result`, return `0`.
- **`WASM_OP_STORE32`** (`access_size = 4, align_mask = 3`):
  - Call `wasm_verify_mem_op(box, insn->base_addr, insn->offset, 4, 3)`. If `< 0`, return error code.
  - Write `(uint32_t)insn->value` to `linear_memory + insn->base_addr + insn->offset`, return `0`.
- **`WASM_OP_LOAD64`** (`access_size = 8, align_mask = 7`):
  - Call `wasm_verify_mem_op(box, insn->base_addr, insn->offset, 8, 7)`. If `< 0`, return error code.
  - Read `uint64_t` from `linear_memory + insn->base_addr + insn->offset`, store into `*out_result`, return `0`.
- **`WASM_OP_STORE64`** (`access_size = 8, align_mask = 7`):
  - Call `wasm_verify_mem_op(box, insn->base_addr, insn->offset, 8, 7)`. If `< 0`, return error code.
  - Write `insn->value` to `linear_memory + insn->base_addr + insn->offset`, return `0`.
- **`WASM_OP_CALL_INDIRECT`**:
  - Check whether `insn->table_idx >= WASM_MAX_TABLE_SLOTS`. If out of range, return `-7` (`WASM_ERR_BAD_TABLE_IDX`).
  - Check whether `!box->table_slots[insn->table_idx].is_valid`. If invalid/empty slot, return `-8` (`WASM_ERR_TABLE_SLOT_EMPTY`).
  - **Type Confusion Protection**: Check whether `box->table_slots[insn->table_idx].type_signature != insn->value`. If type signature hash mismatch, immediately trap and return `-9` (`WASM_ERR_TYPE_CONFUSION`).
  - Store `box->table_slots[insn->table_idx].target_code_id` into `*out_result` and return `0`.
- Return `-1` for any unknown opcode.

#### `int wasm_grow_memory(wasm_sandbox_t *box, uint32_t delta_pages)`
Simulates `memory.grow` to expand linear memory:
- If `!box || !box->is_initialized`, return `-1`.
- Compute current pages: `curr_pages = box->current_memory_bytes / WASM_PAGE_SIZE`.
- If `curr_pages + delta_pages > WASM_MAX_PAGES`, return `-10` (`WASM_ERR_GROW_FAILED`).
- For `i = curr_pages` to `curr_pages + delta_pages - 1`:
  - Set `page_states[i] = PAGE_STATE_MAPPED` and zero out `linear_memory + i * WASM_PAGE_SIZE` (`WASM_PAGE_SIZE` bytes).
- Update `box->current_memory_bytes += delta_pages * WASM_PAGE_SIZE`.
- Return `curr_pages` (old page count prior to growth).

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) simulating 8 rigorous sandbox security scenarios:
1. Normal STORE64/LOAD64, Table Registration, & Type-Safe `CALL_INDIRECT`.
2. Linear Memory Out-of-Bounds Trapping (`base + offset` past mapped boundary).
3. 32-Bit Integer Overflow & Wrap-Around Attack Trapping (`base = 0xFFFFFFF0, offset = 0x20`).
4. Guard Page Hit Trapping (`accessing unmapped guard page after mapped boundary`).
5. Type Confusion Attack Trapping (`CALL_INDIRECT` with mismatched `type_signature`).
6. Memory Alignment Violation Trapping (`STORE64` to odd address offset `3`).
7. Dynamic Memory Growth (`memory.grow`) & Subsequent Valid Access to New Page.
8. Empty Table Slot Invocation Check (`CALL_INDIRECT` on uninitialized index `63`).

If your sandbox engine traps all escape and type-confusion exploits cleanly without ASAN/UBSan anomalies, the driver outputs:
```
cyberbench{sandboxed_wasm_jit_security_state_<64-bit-hex-hash>}
```
