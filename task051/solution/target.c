#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

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

/* Error codes */
#define SGX_ERR_INVALID_ARG     -1
#define SGX_ERR_OUT_OF_MEMORY   -2
#define SGX_ERR_PAGE_NOT_FOUND  -3
#define SGX_ERR_PERM_VIOLATION  -4
#define SGX_ERR_EPCM_BLOCKED    -5
#define SGX_ERR_POINTER_RANGE   -6 /* Iago attack / pointer boundary violation */
#define SGX_ERR_MAC_MISMATCH    -7
#define SGX_ERR_OVERFLOW        -8

void sgx_init_enclave(enclave_engine_t *engine, const uint64_t *initial_mrenclave, const uint8_t *seal_key) {
    if (!engine) return;
    memset(engine, 0, sizeof(enclave_engine_t));
    if (initial_mrenclave) {
        memcpy(engine->mrenclave, initial_mrenclave, sizeof(engine->mrenclave));
    }
    if (seal_key) {
        memcpy(engine->sealing_key, seal_key, sizeof(engine->sealing_key));
    }
    engine->is_initialized = true;
}

int sgx_alloc_page(enclave_engine_t *engine, uint64_t vaddr, uint32_t perms, uint32_t flags) {
    if (!engine || !engine->is_initialized) return SGX_ERR_INVALID_ARG;
    if (vaddr < ENCLAVE_BASE_ADDR || vaddr >= ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES) {
        return SGX_ERR_INVALID_ARG;
    }
    if ((vaddr % EPC_PAGE_SIZE) != 0) {
        return SGX_ERR_INVALID_ARG;
    }
    for (int i = 0; i < EPC_MAX_PAGES; i++) {
        if (engine->epc_pages[i].is_allocated && engine->epc_pages[i].vaddr == vaddr) {
            return SGX_ERR_INVALID_ARG;
        }
    }
    if (engine->allocated_pages >= EPC_MAX_PAGES) {
        return SGX_ERR_OUT_OF_MEMORY;
    }
    for (int i = 0; i < EPC_MAX_PAGES; i++) {
        if (!engine->epc_pages[i].is_allocated) {
            epc_page_t *page = &engine->epc_pages[i];
            page->vaddr = vaddr;
            page->perms = perms;
            page->flags = flags;
            memset(page->data, 0, sizeof(page->data));
            memset(page->mac_tag, 0, sizeof(page->mac_tag));
            page->is_allocated = true;
            engine->allocated_pages++;
            return 0;
        }
    }
    return SGX_ERR_OUT_OF_MEMORY;
}

int sgx_check_memory_access(const enclave_engine_t *engine, uint64_t vaddr, size_t len, uint32_t req_perms) {
    if (!engine || !engine->is_initialized || len == 0) return SGX_ERR_INVALID_ARG;
    if (vaddr + len < vaddr) return SGX_ERR_OVERFLOW;
    if (vaddr < ENCLAVE_BASE_ADDR || vaddr + len > ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES) {
        return SGX_ERR_POINTER_RANGE;
    }
    uint64_t start_page = vaddr & ~(EPC_PAGE_SIZE - 1ULL);
    uint64_t end_addr = vaddr + len;
    for (uint64_t p = start_page; p < end_addr; p += EPC_PAGE_SIZE) {
        const epc_page_t *page = NULL;
        for (int i = 0; i < EPC_MAX_PAGES; i++) {
            if (engine->epc_pages[i].is_allocated && engine->epc_pages[i].vaddr == p) {
                page = &engine->epc_pages[i];
                break;
            }
        }
        if (!page) return SGX_ERR_PAGE_NOT_FOUND;
        if (page->flags & EPCM_BLOCKED) return SGX_ERR_EPCM_BLOCKED;
        if ((page->perms & req_perms) != req_perms) return SGX_ERR_PERM_VIOLATION;
    }
    return 0;
}

int sgx_validate_ecall_pointer_range(const enclave_engine_t *engine, uint64_t untrusted_ptr, size_t len) {
    if (!engine || !engine->is_initialized || len == 0) return SGX_ERR_INVALID_ARG;
    if (untrusted_ptr + len < untrusted_ptr) return SGX_ERR_OVERFLOW;
    /* Must not overlap or point inside enclave address range */
    if (!(untrusted_ptr + len <= ENCLAVE_BASE_ADDR || untrusted_ptr >= ENCLAVE_BASE_ADDR + ENCLAVE_SIZE_BYTES)) {
        return SGX_ERR_POINTER_RANGE;
    }
    return 0;
}

int sgx_process_ecall(enclave_engine_t *engine, const ecall_request_t *req, uint64_t target_vaddr, uint8_t *out_buffer, size_t out_max_len) {
    if (!engine || !engine->is_initialized || !req || !out_buffer || out_max_len == 0 || req->num_args > MAX_CALL_ARGS) {
        return SGX_ERR_INVALID_ARG;
    }
    int ptr_check = sgx_validate_ecall_pointer_range(engine, (uint64_t)(uintptr_t)out_buffer, out_max_len);
    if (ptr_check != 0) return ptr_check;

    for (uint32_t i = 0; i < req->num_args; i++) {
        if (req->arg_lens[i] > 0) {
            int arg_check = sgx_validate_ecall_pointer_range(engine, req->arg_ptrs[i], req->arg_lens[i]);
            if (arg_check != 0) return arg_check;
        }
    }

    int mem_check = sgx_check_memory_access(engine, target_vaddr, out_max_len, PAGE_PERM_READ | PAGE_PERM_EXEC);
    if (mem_check != 0) return mem_check;

    for (int i = 0; i < EPC_MAX_PAGES; i++) {
        if (engine->epc_pages[i].is_allocated && engine->epc_pages[i].vaddr == target_vaddr) {
            memcpy(out_buffer, engine->epc_pages[i].data, (out_max_len < EPC_PAGE_SIZE) ? out_max_len : EPC_PAGE_SIZE);
            return 0;
        }
    }
    return SGX_ERR_PAGE_NOT_FOUND;
}

/* Verification test suite in main() */
int main(void) {
    enclave_engine_t engine;
    uint64_t mrenclave[4] = { 0x1111, 0x2222, 0x3333, 0x4444 };
    uint8_t key[32] = { 0xAA };
    sgx_init_enclave(&engine, mrenclave, key);

    int passed = 0;
    int total = 8;

    /* Test 1: Normal allocation and ECALL execution */
    if (sgx_alloc_page(&engine, ENCLAVE_BASE_ADDR, PAGE_PERM_READ | PAGE_PERM_EXEC, EPCM_VALID) == 0) {
        uint8_t host_out[64];
        ecall_request_t req;
        memset(&req, 0, sizeof(req));
        req.call_id = 1;
        req.num_args = 1;
        req.arg_ptrs[0] = 0x10000000ULL; /* untrusted host memory */
        req.arg_lens[0] = 32;
        if (sgx_process_ecall(&engine, &req, ENCLAVE_BASE_ADDR, host_out, sizeof(host_out)) == 0) {
            passed++;
        }
    }

    /* Test 2: ECALL Iago attack trapping (input pointer inside enclave space) */
    ecall_request_t bad_req1;
    memset(&bad_req1, 0, sizeof(bad_req1));
    bad_req1.call_id = 2;
    bad_req1.num_args = 1;
    bad_req1.arg_ptrs[0] = ENCLAVE_BASE_ADDR + 0x100; /* inside enclave */
    bad_req1.arg_lens[0] = 64;
    uint8_t host_out2[32];
    if (sgx_process_ecall(&engine, &bad_req1, ENCLAVE_BASE_ADDR, host_out2, sizeof(host_out2)) == SGX_ERR_POINTER_RANGE) {
        passed++;
    }

    /* Test 3: ECALL Iago attack trapping (pointer arithmetic wrap-around overflow) */
    ecall_request_t bad_req2;
    memset(&bad_req2, 0, sizeof(bad_req2));
    bad_req2.call_id = 3;
    bad_req2.num_args = 1;
    bad_req2.arg_ptrs[0] = 0xFFFFFFFFFFFFF000ULL;
    bad_req2.arg_lens[0] = 0x2000; /* overflows around 0 */
    if (sgx_process_ecall(&engine, &bad_req2, ENCLAVE_BASE_ADDR, host_out2, sizeof(host_out2)) == SGX_ERR_OVERFLOW) {
        passed++;
    }

    /* Test 4: EPCM blocked state check */
    sgx_alloc_page(&engine, ENCLAVE_BASE_ADDR + 0x1000, PAGE_PERM_READ, EPCM_VALID | EPCM_BLOCKED);
    if (sgx_check_memory_access(&engine, ENCLAVE_BASE_ADDR + 0x1000, 64, PAGE_PERM_READ) == SGX_ERR_EPCM_BLOCKED) {
        passed++;
    }

    /* Test 5: Permission violation check */
    sgx_alloc_page(&engine, ENCLAVE_BASE_ADDR + 0x2000, PAGE_PERM_WRITE, EPCM_VALID);
    if (sgx_check_memory_access(&engine, ENCLAVE_BASE_ADDR + 0x2000, 64, PAGE_PERM_READ) == SGX_ERR_PERM_VIOLATION) {
        passed++;
    }

    /* Test 6: Page not found inside enclave range check */
    if (sgx_check_memory_access(&engine, ENCLAVE_BASE_ADDR + 0x5000, 64, PAGE_PERM_READ) == SGX_ERR_PAGE_NOT_FOUND) {
        passed++;
    }

    /* Test 7: Page alignment and boundary check */
    if (sgx_alloc_page(&engine, ENCLAVE_BASE_ADDR - 0x1000, PAGE_PERM_READ, EPCM_VALID) == SGX_ERR_INVALID_ARG &&
        sgx_alloc_page(&engine, ENCLAVE_BASE_ADDR + 123, PAGE_PERM_READ, EPCM_VALID) == SGX_ERR_INVALID_ARG) {
        passed++;
    }

    /* Test 8: Pointer range validation function check directly */
    if (sgx_validate_ecall_pointer_range(&engine, 0x1000, 0x1000) == 0 &&
        sgx_validate_ecall_pointer_range(&engine, ENCLAVE_BASE_ADDR - 0x10, 0x100) == SGX_ERR_POINTER_RANGE) {
        passed++;
    }

    if (passed == total) {
        printf("cyberbench{sgx_enclave_epc_memory_security_state_7d3a91e4b802fc5a}\n");
        return 0;
    } else {
        printf("FAILED checks: %d/%d passed\n", passed, total);
        return 1;
    }
}
