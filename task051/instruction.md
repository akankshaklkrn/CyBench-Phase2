# Level 0 Challenge: SGX Enclave EPC & ECALL/OCALL Pointer Boundary Security Engine (`sgx_enclave_epc_memory_security_l0`)

You are tasked with implementing a **Zero-Trust Trusted Execution Environment (TEE) SGX Enclave Memory & Pointer Boundary Verification Engine** inside a confidential computing runtime. Intel SGX enclaves isolate private code and data inside Enclave Page Cache (`EPC`) memory (`ENCLAVE_BASE_ADDR`). When untrusted host applications enter the enclave (`ECALL`) or pass input/output structures (`ecall_request_t`), the enclave MUST enforce strict memory boundary and permission checks. Any failure to validate untrusted host pointer ranges (`[untrusted_ptr, untrusted_ptr + len)`) allows attackers to launch **Iago attacks** or memory corruption exploits where untrusted pointers point directly into private enclave memory, tricking the enclave into overwriting or reading its own secrets.

## System Specification

The verification engine (`enclave_engine_t`) manages allocated EPC pages (`epc_pages`), measurement values (`mrenclave`), sealing keys (`sealing_key`), and processes ECALL requests safely.

### 1. Engine & Enclave Structures

```c
#define ENCLAVE_BASE_ADDR  0x80000000ULL
#define ENCLAVE_SIZE_BYTES 0x00100000ULL /* 1 MB enclave address space */
#define EPC_MAX_PAGES      64
#define EPC_PAGE_SIZE      4096
#define MAX_CALL_ARGS      8
#define MAX_BUFFER_BYTES   1024

typedef enum {
    PAGE_PERM_READ  = 0x01,
    PAGE_PERM_WRITE = 0x02,
    PAGE_PERM_EXEC  = 0x04
} epc_perm_t;

typedef enum {
    EPCM_VALID   = 0x01,
    EPCM_BLOCKED = 0x02,
    EPCM_PENDING = 0x04
} epcm_flags_t;

typedef struct {
    uint64_t vaddr;
    uint32_t perms;
    uint32_t flags;
    uint8_t  data[EPC_PAGE_SIZE];
    uint8_t  mac_tag[32];
    bool     is_allocated;
} epc_page_t;

typedef struct {
    uint32_t call_id;
    uint64_t arg_ptrs[MAX_CALL_ARGS];
    uint32_t arg_lens[MAX_CALL_ARGS];
    uint32_t num_args;
} ecall_request_t;

typedef struct {
    epc_page_t epc_pages[EPC_MAX_PAGES];
    uint64_t   mrenclave[4];
    uint8_t    sealing_key[32];
    uint32_t   allocated_pages;
    bool       is_initialized;
} enclave_engine_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void sgx_init_enclave(enclave_engine_t *engine, const uint64_t *initial_mrenclave, const uint8_t *seal_key)`
Initializes the zero-trust SGX enclave runtime:
- If `!engine`, return immediately.
- Zero out `engine`, copy `initial_mrenclave[0..3]` to `engine->mrenclave` (if non-null), and `seal_key[0..31]` to `engine->sealing_key` (if non-null).
- Set `engine->is_initialized = true`.

#### `int sgx_alloc_page(enclave_engine_t *engine, uint64_t vaddr, uint32_t perms, uint32_t flags)`
Allocates a new Enclave Page Cache page at `vaddr`:
- If `!engine || !engine->is_initialized`, return `-1` (`SGX_ERR_INVALID_ARG`).
- Verify that `vaddr` lies strictly within enclave address range `[ENCLAVE_BASE_ADDR, ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES)` and is 4KB page-aligned (`vaddr % EPC_PAGE_SIZE == 0`). If not, return `-1`.
- Check whether `vaddr` is already allocated in `epc_pages`. If so, return `-1`.
- Check if `allocated_pages >= EPC_MAX_PAGES`. If full, return `-2` (`SGX_ERR_OUT_OF_MEMORY`).
- Locate the first inactive slot (`!is_allocated`), set `vaddr`, `perms`, `flags`, zero out `data` and `mac_tag`, set `is_allocated = true`, increment `allocated_pages`, and return `0`.

#### `int sgx_check_memory_access(const enclave_engine_t *engine, uint64_t vaddr, size_t len, uint32_t req_perms)`
Validates that a virtual memory range inside the enclave is allocated, unblocked, and possesses requested permissions:
- If `!engine || !engine->is_initialized || len == 0`, return `-1`.
- Check for pointer arithmetic overflow: `if (vaddr + len < vaddr)` return `-8` (`SGX_ERR_OVERFLOW`).
- Verify that `[vaddr, vaddr + len)` is strictly inside enclave memory: `vaddr < ENCLAVE_BASE_ADDR || vaddr + len > ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES` -> return `-6` (`SGX_ERR_POINTER_RANGE`).
- Iterate over every 4KB page boundary covered by `[vaddr, vaddr + len)`:
  - Find matching allocated `epc_page_t`. If missing, return `-3` (`SGX_ERR_PAGE_NOT_FOUND`).
  - If `page->flags & EPCM_BLOCKED`, return `-5` (`SGX_ERR_EPCM_BLOCKED`).
  - If `(page->perms & req_perms) != req_perms`, return `-4` (`SGX_ERR_PERM_VIOLATION`).
- Return `0` if all checks pass.

#### `int sgx_validate_ecall_pointer_range(const enclave_engine_t *engine, uint64_t untrusted_ptr, size_t len)`
**Critical Iago Attack Prevention**: When untrusted host applications invoke an ECALL, any pointer passed from the outside MUST point exclusively to untrusted host memory outside the enclave:
- If `!engine || !engine->is_initialized || len == 0`, return `-1`.
- Check for pointer arithmetic overflow: `if (untrusted_ptr + len < untrusted_ptr)` return `-8` (`SGX_ERR_OVERFLOW`).
- Check whether `[untrusted_ptr, untrusted_ptr + len)` overlaps or falls inside enclave address range `[ENCLAVE_BASE_ADDR, ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES)`:
  - If `!(untrusted_ptr + len <= ENCLAVE_BASE_ADDR || untrusted_ptr >= ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES)`, return `-6` (`SGX_ERR_POINTER_RANGE`).
- Return `0` if the range is strictly outside the enclave.

#### `int sgx_process_ecall(enclave_engine_t *engine, const ecall_request_t *req, uint64_t target_vaddr, uint8_t *out_buffer, size_t out_max_len)`
Processes an ECALL request securely across memory boundaries:
- If `!engine || !engine->is_initialized || !req || !out_buffer || out_max_len == 0 || req->num_args > MAX_CALL_ARGS`, return `-1`.
- Check that the destination buffer pointer `out_buffer` (passed to untrusted host) is safely outside enclave range using `sgx_validate_ecall_pointer_range(engine, (uint64_t)(uintptr_t)out_buffer, out_max_len)`. If not `0`, return the error code.
- For each argument `i` in `0..req->num_args - 1`:
  - If `arg_lens[i] > 0`, check `sgx_validate_ecall_pointer_range(engine, req->arg_ptrs[i], req->arg_lens[i])`. If not `0`, trap the Iago attack and return `-6`.
- Verify internal enclave memory access for `target_vaddr` by calling `sgx_check_memory_access(engine, target_vaddr, out_max_len, PAGE_PERM_READ | PAGE_PERM_EXEC)`. If not `0`, return the error code.
- Locate the page matching `target_vaddr`, copy up to `out_max_len` bytes (capped at `EPC_PAGE_SIZE`) from `page->data` into `out_buffer`, and return `0`.

## Verification & Testing

Your implementation will be evaluated against a rigorous test suite (`main` in `target.c`) executing 8 zero-trust SGX scenarios:
1. Normal page allocation (`sgx_alloc_page`), memory access check (`sgx_check_memory_access`), and ECALL execution (`sgx_process_ecall == 0`).
2. ECALL Iago attack trapping (`req.arg_ptrs[0]` pointing inside enclave memory returns `SGX_ERR_POINTER_RANGE`).
3. ECALL pointer arithmetic wrap-around overflow check (`0xFFFFFFFFFFFFF000ULL` + `0x2000` returns `SGX_ERR_OVERFLOW`).
4. Enclave Page Cache Map blocked state check (`EPCM_BLOCKED` returns `SGX_ERR_EPCM_BLOCKED`).
5. Memory access permission violation check (`PAGE_PERM_WRITE` only page read returns `SGX_ERR_PERM_VIOLATION`).
6. Page not found check inside enclave range returns `SGX_ERR_PAGE_NOT_FOUND`.
7. Page boundary and 4KB alignment checks return `SGX_ERR_INVALID_ARG`.
8. Direct pointer range validation function check (`sgx_validate_ecall_pointer_range`).

When all checks pass without memory errors, the driver outputs:
```
cyberbench{sgx_enclave_epc_memory_security_state_7d3a91e4b802fc5a}
```
