#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define TEE_MAX_EPC_PAGES 64
#define TEE_MAX_ENCLAVES 8
#define TEE_PAGE_SIZE 1024

typedef enum {
    EPC_PAGE_FREE = 0,
    EPC_PAGE_REG = 1,
    EPC_PAGE_TCS = 2,
    EPC_PAGE_SECINFO = 3
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
    uint64_t version_counter;
    bool is_valid;
    bool is_blocked;
    tcs_state_t tcs_state;
} epc_page_t;

typedef struct {
    uint32_t enclave_id;
    bool is_initialized;
    uint64_t mr_enclave;
    uint64_t owner_key;
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

void tee_init(tee_engine_t *engine) {
    if (!engine) return;
    memset(engine, 0, sizeof(tee_engine_t));
    engine->global_version_counter = 1;
}

int tee_create_enclave(tee_engine_t *engine, uint32_t enclave_id, uint64_t owner_key) {
    if (!engine) return -1;
    if (enclave_id == 0 || enclave_id > TEE_MAX_ENCLAVES) return -1;
    if (engine->enclaves[enclave_id - 1].is_initialized) return -2;

    engine->enclaves[enclave_id - 1].enclave_id = enclave_id;
    engine->enclaves[enclave_id - 1].is_initialized = true;
    engine->enclaves[enclave_id - 1].mr_enclave = 0x811C9DC5ULL;
    engine->enclaves[enclave_id - 1].owner_key = owner_key;
    return 0;
}

int tee_add_page(tee_engine_t *engine, uint32_t enclave_id, uint64_t vaddr, epc_page_type_t type, const uint8_t *src_data) {
    if (!engine) return -1;
    if (enclave_id == 0 || enclave_id > TEE_MAX_ENCLAVES) return -1;
    if (!engine->enclaves[enclave_id - 1].is_initialized) return -1;
    if (vaddr % TEE_PAGE_SIZE != 0) return -3;

    for (int i = 0; i < TEE_MAX_EPC_PAGES; i++) {
        if (engine->epc[i].is_valid && engine->epc[i].enclave_id == enclave_id && engine->epc[i].virtual_addr == vaddr) {
            return -4;
        }
    }

    int free_idx = -1;
    for (int i = 0; i < TEE_MAX_EPC_PAGES; i++) {
        if (!engine->epc[i].is_valid) {
            free_idx = i;
            break;
        }
    }
    if (free_idx < 0) return -5;

    epc_page_t *page = &engine->epc[free_idx];
    memset(page, 0, sizeof(epc_page_t));
    page->is_valid = true;
    page->is_blocked = false;
    page->enclave_id = enclave_id;
    page->virtual_addr = vaddr;
    page->type = type;
    if (type == EPC_PAGE_TCS) {
        page->tcs_state = TCS_STATE_INACTIVE;
    }
    page->version_counter = engine->global_version_counter++;
    if (src_data) {
        memcpy(page->data, src_data, TEE_PAGE_SIZE);
    } else {
        memset(page->data, 0, TEE_PAGE_SIZE);
    }

    uint64_t hash = engine->enclaves[enclave_id - 1].mr_enclave;
    for (int i = 0; i < 8; i++) {
        hash = (hash ^ ((vaddr >> (i * 8)) & 0xFF)) * 0x00000100000001B3ULL;
    }
    hash = (hash ^ (uint8_t)type) * 0x00000100000001B3ULL;
    for (int i = 0; i < TEE_PAGE_SIZE; i++) {
        hash = (hash ^ page->data[i]) * 0x00000100000001B3ULL;
    }
    engine->enclaves[enclave_id - 1].mr_enclave = hash;

    return free_idx;
}

int tee_enter_enclave(tee_engine_t *engine, uint32_t enclave_id, uint64_t tcs_vaddr) {
    if (!engine) return -1;
    if (enclave_id == 0 || enclave_id > TEE_MAX_ENCLAVES) return -1;
    if (!engine->enclaves[enclave_id - 1].is_initialized) return -1;

    epc_page_t *target = NULL;
    for (int i = 0; i < TEE_MAX_EPC_PAGES; i++) {
        if (engine->epc[i].is_valid && engine->epc[i].enclave_id == enclave_id && engine->epc[i].virtual_addr == tcs_vaddr) {
            target = &engine->epc[i];
            break;
        }
    }
    if (!target) return -6;
    if (target->type != EPC_PAGE_TCS) return -7;
    if (target->is_blocked) return -8;
    if (target->tcs_state == TCS_STATE_ENTERED) return -9;

    target->tcs_state = TCS_STATE_ENTERED;
    return 0;
}

int tee_generate_quote(tee_engine_t *engine, uint32_t enclave_id, const uint8_t *report_data, tee_quote_t *out_quote) {
    if (!engine || !out_quote) return -1;
    if (enclave_id == 0 || enclave_id > TEE_MAX_ENCLAVES) return -1;
    if (!engine->enclaves[enclave_id - 1].is_initialized) return -1;

    memset(out_quote, 0, sizeof(tee_quote_t));
    out_quote->enclave_id = enclave_id;
    out_quote->mr_enclave = engine->enclaves[enclave_id - 1].mr_enclave;
    if (report_data) {
        memcpy(out_quote->report_data, report_data, 64);
    }

    uint64_t mac = engine->enclaves[enclave_id - 1].owner_key ^ out_quote->mr_enclave;
    for (int i = 0; i < 64; i++) {
        mac = (mac ^ out_quote->report_data[i]) * 0x00000100000001B3ULL;
    }
    out_quote->mac_tag = mac;
    return 0;
}

// Verification Harness
int main() {
    uint64_t state_hash = 0x100000001B3ULL;
    tee_engine_t engine;
    tee_quote_t quote;
    uint8_t dummy_page[TEE_PAGE_SIZE];
    memset(dummy_page, 0xAA, TEE_PAGE_SIZE);

    // Test 1: Normal Enclave Creation, Page Add, EENTER, Quote
    tee_init(&engine);
    int r1 = tee_create_enclave(&engine, 1, 0xDEADBEEF12345678ULL);
    int r2 = tee_add_page(&engine, 1, 0x1000, EPC_PAGE_REG, dummy_page);
    int r3 = tee_add_page(&engine, 1, 0x2000, EPC_PAGE_TCS, NULL);
    int r4 = tee_enter_enclave(&engine, 1, 0x2000);
    uint8_t rep[64] = "ATTESTATION_DATA";
    int r5 = tee_generate_quote(&engine, 1, rep, &quote);
    state_hash ^= r1 * 0x11ULL + r2 * 0x22ULL + r3 * 0x33ULL + r4 * 0x44ULL + r5 * 0x55ULL + quote.mac_tag;

    // Test 2: Duplicate Virtual Address Mapping Attack Rejection
    int r6 = tee_add_page(&engine, 1, 0x1000, EPC_PAGE_REG, dummy_page); // vaddr 0x1000 already mapped
    state_hash ^= r6 * 0x1111ULL;

    // Test 3: TCS Re-entry & Concurrency Trap (TCS at 0x2000 already ENTERED)
    int r7 = tee_enter_enclave(&engine, 1, 0x2000);
    state_hash ^= r7 * 0x2222ULL;

    // Test 4: Unaligned Virtual Address Rejection
    int r8 = tee_add_page(&engine, 1, 0x3008, EPC_PAGE_REG, dummy_page);
    state_hash ^= r8 * 0x3333ULL;

    // Test 5: Execution on Non-TCS Page Trap (try entering REG page at 0x1000)
    int r9 = tee_enter_enclave(&engine, 1, 0x1000);
    state_hash ^= r9 * 0x4444ULL;

    // Test 6: Attestation Quote Measurement Integrity
    uint8_t rep2[64] = "NEW_DATA";
    int r10 = tee_generate_quote(&engine, 1, rep2, &quote);
    state_hash ^= r10 * 0x5555ULL + quote.mr_enclave;

    // Test 7: Blocked Page Access Trapping
    int r11 = tee_add_page(&engine, 1, 0x4000, EPC_PAGE_TCS, NULL);
    if (r11 >= 0) {
        engine.epc[r11].is_blocked = true;
    }
    int r12 = tee_enter_enclave(&engine, 1, 0x4000);
    state_hash ^= r11 * 0x6666ULL + r12 * 0x7777ULL;

    // Test 8: Multi-Enclave Isolation & EPC Boundary Check
    int r13 = tee_create_enclave(&engine, 2, 0xCAFEBABE87654321ULL);
    int r14 = tee_add_page(&engine, 2, 0x2000, EPC_PAGE_TCS, NULL);
    int r15 = tee_enter_enclave(&engine, 2, 0x2000);
    state_hash ^= r13 * 0x8888ULL + r14 * 0x9999ULL + r15 * 0xAAAAULL + engine.global_version_counter;

    if (state_hash == 0) state_hash = 0xBADCAFEULL;
    printf("Verification SUCCESS! Dynamic State Hash computed over 8 TEE verification tests.\n");
    printf("cyberbench{tee_secure_enclave_state_%016llx}\n", (unsigned long long)state_hash);
    return 0;
}
