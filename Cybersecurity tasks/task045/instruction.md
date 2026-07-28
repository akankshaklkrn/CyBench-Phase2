# Level 0 Challenge: TEE Secure Enclave Memory Management & Attestation Engine (`tee_secure_enclave_l0`)

You are tasked with implementing a **Trusted Execution Environment (TEE) Secure Enclave Memory Management & Cryptographic Attestation Engine** inside a simulated hardware isolation controller. Hardware secure enclaves (such as Intel SGX/TDX or ARM TrustZone/CCA) protect sensitive computations from compromised host operating systems (ring 0) through strict memory encryption, hardware-enforced access control rules, monotonic replay protection counters, and cryptographic measurement quotes. Any logical flaw in page ownership checks, Thread Control Structure (`TCS`) state transitions, or quote generation allows host ring 0 injection and enclave secrets extraction.

## System Specification

The hardware engine (`tee_engine_t`) manages an Encrypted Page Cache (`EPC`) containing 64 physical pages (`epc_page_t`), tracking ownership (`enclave_id`), page types, access rights, and replay protection version counters.

### 1. Hardware & Enclave Structures

```c
#define TEE_MAX_EPC_PAGES 64
#define TEE_MAX_ENCLAVES 8
#define TEE_PAGE_SIZE 1024

typedef enum {
    EPC_PAGE_FREE = 0,
    EPC_PAGE_REG = 1,       // Regular data/code page
    EPC_PAGE_TCS = 2,       // Thread Control Structure page (entry/exit)
    EPC_PAGE_SECINFO = 3    // Enclave security attributes & metadata page
} epc_page_type_t;

typedef enum {
    TCS_STATE_INACTIVE = 0,
    TCS_STATE_ENTERED = 1
} tcs_state_t;

typedef struct {
    epc_page_type_t type;
    uint32_t enclave_id;
    uint64_t virtual_addr;
    uint8_t data[TEE_PAGE_SIZE];
    uint64_t version_counter; // Monotonic counter against replay/rollback attacks
    bool is_valid;
    bool is_blocked;          // Blocked from new accesses during eviction/teardown
    tcs_state_t tcs_state;    // Only valid if type == EPC_PAGE_TCS
} epc_page_t;

typedef struct {
    uint32_t enclave_id;
    bool is_initialized;
    uint64_t mr_enclave;      // Cryptographic measurement hash of all loaded pages
    uint64_t owner_key;       // Enclave signing/attestation key derived by hardware
} enclave_info_t;

typedef struct {
    epc_page_t epc[TEE_MAX_EPC_PAGES];
    enclave_info_t enclaves[TEE_MAX_ENCLAVES];
    uint64_t global_version_counter;
} tee_engine_t;

typedef struct {
    uint32_t enclave_id;
    uint64_t mr_enclave;
    uint8_t report_data[64];
    uint64_t mac_tag;
} tee_quote_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void tee_init(tee_engine_t *engine)`
Initializes the TEE hardware isolation controller:
- Zeroes out all 64 `epc` pages (`is_valid = false`, `type = EPC_PAGE_FREE`).
- Zeroes out all 8 `enclaves` entries (`is_initialized = false`).
- Initializes `global_version_counter = 1`.

#### `int tee_create_enclave(tee_engine_t *engine, uint32_t enclave_id, uint64_t owner_key)`
Registers a new secure enclave ID (`1` through `8`):
- If `enclave_id == 0` or `enclave_id > TEE_MAX_ENCLAVES`, return `-1` (`TEE_ERR_INVALID_ID`).
- If `engine->enclaves[enclave_id - 1].is_initialized`, return `-2` (`TEE_ERR_ALREADY_EXISTS`).
- Initialize `engine->enclaves[enclave_id - 1]` with `enclave_id`, `is_initialized = true`, `mr_enclave = 0x811C9DC5` (FNV-1a offset basis), and `owner_key`.
- Return `0` on success.

#### `int tee_add_page(tee_engine_t *engine, uint32_t enclave_id, uint64_t vaddr, epc_page_type_t type, const uint8_t *src_data)`
Allocates and measures an EPC page for an enclave during load/build time:
- Enforce `enclave_id >= 1 && enclave_id <= TEE_MAX_ENCLAVES` and verify enclave is initialized (`is_initialized == true`).
- Check that virtual address `vaddr` is page-aligned (`vaddr % TEE_PAGE_SIZE == 0`). If not, return `-3` (`TEE_ERR_ALIGNMENT`).
- **TOCTOU / Double-Mapping Check**: Verify that no existing valid EPC page (`is_valid == true`) belongs to `enclave_id` with the same `virtual_addr`. If a duplicate virtual address mapping exists, return `-4` (`TEE_ERR_DUPLICATE_MAP`).
- Find the first free EPC slot (`is_valid == false`). If EPC is full (`64` pages), return `-5` (`TEE_ERR_OUT_OF_MEMORY`).
- Allocate slot:
  - Set `is_valid = true`, `is_blocked = false`, `enclave_id`, `virtual_addr = vaddr`, `type`.
  - If `type == EPC_PAGE_TCS`, initialize `tcs_state = TCS_STATE_INACTIVE`.
  - Set `version_counter = engine->global_version_counter++`.
  - If `src_data` is non-null, copy `TEE_PAGE_SIZE` bytes into `data`; otherwise zero out `data`.
- **Measurement Update (`mr_enclave`)**:
  - Update `enclaves[enclave_id - 1].mr_enclave` using FNV-1a 64-bit across `vaddr` (all 8 bytes, little-endian/host), `type` (1 byte), and the `1024` bytes of `data`:
    ```c
    uint64_t hash = engine->enclaves[enclave_id - 1].mr_enclave;
    for (int i = 0; i < 8; i++) hash = (hash ^ ((vaddr >> (i * 8)) & 0xFF)) * 0x00000100000001B3ULL;
    hash = (hash ^ (uint8_t)type) * 0x00000100000001B3ULL;
    for (int i = 0; i < TEE_PAGE_SIZE; i++) hash = (hash ^ data[i]) * 0x00000100000001B3ULL;
    engine->enclaves[enclave_id - 1].mr_enclave = hash;
    ```
- Return the allocated EPC slot index (`0` to `63`).

#### `int tee_enter_enclave(tee_engine_t *engine, uint32_t enclave_id, uint64_t tcs_vaddr)`
Simulates hardware `EENTER` transition into the enclave:
- Enforce `enclave_id >= 1 && enclave_id <= TEE_MAX_ENCLAVES` and verify enclave is initialized.
- Locate the valid EPC page (`is_valid == true`) matching `enclave_id` and `virtual_addr == tcs_vaddr`. If not found, return `-6` (`TEE_ERR_PAGE_NOT_FOUND`).
- Verify `page->type == EPC_PAGE_TCS`. If not a TCS page, return `-7` (`TEE_ERR_NOT_TCS`).
- Verify `page->is_blocked == false`. If blocked, return `-8` (`TEE_ERR_PAGE_BLOCKED`).
- **Thread Concurrency & Re-entry Check**: If `page->tcs_state == TCS_STATE_ENTERED`, return `-9` (`TEE_ERR_TCS_BUSY`).
- Mark `page->tcs_state = TCS_STATE_ENTERED` and return `0`.

#### `int tee_generate_quote(tee_engine_t *engine, uint32_t enclave_id, const uint8_t *report_data, tee_quote_t *out_quote)`
Generates a cryptographic hardware attestation quote for an enclave:
- Enforce `enclave_id >= 1 && enclave_id <= TEE_MAX_ENCLAVES` and check initialization.
- Copy `enclave_id` and `mr_enclave` into `out_quote`.
- If `report_data` is provided, copy `64` bytes into `out_quote->report_data`; otherwise zero it.
- Compute hardware `mac_tag` over `mr_enclave` and `report_data[0..63]` mixed with the enclave `owner_key`:
  ```c
  uint64_t mac = engine->enclaves[enclave_id - 1].owner_key ^ out_quote->mr_enclave;
  for (int i = 0; i < 64; i++) {
      mac = (mac ^ out_quote->report_data[i]) * 0x00000100000001B3ULL;
  }
  out_quote->mac_tag = mac;
  ```
- Return `0` on success.

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) simulating 8 rigorous hardware enclave security scenarios:
1. Normal Enclave Creation, REG/TCS Page Allocation, EENTER Transition, & Attestation Quote Generation.
2. Duplicate Virtual Address Mapping Rejection (`vaddr` double-map attack during `tee_add_page`).
3. TCS Re-entry & Concurrency Trap (`EENTER` on an already `ENTERED` TCS page).
4. Unaligned Virtual Address Rejection (`vaddr % 1024 != 0`).
5. Execution on Non-TCS Page Trap (`EENTER` attempting to jump directly into a regular `REG` or `SECINFO` page without passing through TCS).
6. Attestation Quote Measurement Integrity & `owner_key` MAC Verification.
7. Blocked Page Access Trapping during Eviction/Teardown Simulation (`is_blocked = true`).
8. Multi-Enclave Isolation & EPC Page Exhaustion Boundary Check (`64` pages limit).

If your secure enclave engine satisfies all hardware isolation, attestation, and state invariants cleanly without memory faults, the verification driver outputs:
```
cyberbench{tee_secure_enclave_state_<64-bit-hex-hash>}
```
