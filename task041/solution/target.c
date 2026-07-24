#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define PTE_PRESENT  0x01
#define PTE_RW       0x02
#define PTE_USER     0x04
#define PTE_ACCESSED 0x20
#define PTE_DIRTY    0x40

#define ACCESS_READ  0x01
#define ACCESS_WRITE 0x02
#define ACCESS_USER  0x04

#define FAULT_P      0x01
#define FAULT_WR     0x02
#define FAULT_US     0x04

#define PAGE_SIZE    4096
#define TLB_SIZE     16

typedef struct {
    bool valid;
    uint32_t vpn;        // Virtual Page Number (gva & ~0xFFF)
    uint32_t ppn;        // Physical Page Number (hpa & ~0xFFF)
    uint32_t flags;      // Cached PTE permissions
} tlb_entry_t;

typedef struct {
    uint8_t *phys_memory;
    uint32_t phys_mem_size;
    uint32_t guest_cr3;
    tlb_entry_t tlb[TLB_SIZE];
    uint32_t tlb_rr_idx;
    uint32_t tlb_hits;
    uint32_t tlb_misses;
} mmu_ctx_t;

/* Flush all entries in Software TLB */
void mmu_tlb_flush(mmu_ctx_t *ctx) {
    for (int i = 0; i < TLB_SIZE; i++) {
        ctx->tlb[i].valid = false;
    }
}

/* Invalidate specific page in Software TLB */
void mmu_invlpg(mmu_ctx_t *ctx, uint32_t gva) {
    uint32_t vpn = gva & ~0xFFF;
    for (int i = 0; i < TLB_SIZE; i++) {
        if (ctx->tlb[i].valid && ctx->tlb[i].vpn == vpn) {
            ctx->tlb[i].valid = false;
        }
    }
}

/* Perform hierarchical 3-level page walk and TLB lookup */
bool mmu_translate_gva(mmu_ctx_t *ctx, uint32_t gva, uint32_t access_flags, uint32_t *out_hpa, uint32_t *out_fault_error) {
    uint32_t vpn = gva & ~0xFFF;
    uint32_t off = gva & 0xFFF;

    /* 1. Check Software TLB */
    for (int i = 0; i < TLB_SIZE; i++) {
        if (ctx->tlb[i].valid && ctx->tlb[i].vpn == vpn) {
            uint32_t cached_flags = ctx->tlb[i].flags;
            /* Check permissions against cached entry */
            if ((access_flags & ACCESS_USER) && !(cached_flags & PTE_USER)) {
                *out_fault_error = FAULT_P | FAULT_US | ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0);
                return false;
            }
            if ((access_flags & ACCESS_WRITE) && !(cached_flags & PTE_RW)) {
                *out_fault_error = FAULT_P | FAULT_WR | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
                return false;
            }
            ctx->tlb_hits++;
            *out_hpa = ctx->tlb[i].ppn + off;
            return true;
        }
    }

    ctx->tlb_misses++;

    /* 2. Perform 3-Level Page Walk */
    uint32_t pdpt_idx = (gva >> 22) & 0x3FF;
    uint32_t pd_idx   = (gva >> 16) & 0x3F;
    uint32_t pt_idx   = (gva >> 12) & 0xF;

    if (ctx->guest_cr3 + pdpt_idx * 4 + 4 > ctx->phys_mem_size) {
        *out_fault_error = 0;
        return false;
    }
    uint32_t *pdpt = (uint32_t *)(ctx->phys_memory + ctx->guest_cr3);
    uint32_t pdpt_entry = pdpt[pdpt_idx];
    if (!(pdpt_entry & PTE_PRESENT)) {
        *out_fault_error = ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0) | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }
    if ((access_flags & ACCESS_USER) && !(pdpt_entry & PTE_USER)) {
        *out_fault_error = FAULT_P | FAULT_US | ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0);
        return false;
    }
    if ((access_flags & ACCESS_WRITE) && !(pdpt_entry & PTE_RW)) {
        *out_fault_error = FAULT_P | FAULT_WR | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }

    uint32_t pd_base = pdpt_entry & ~0xFFF;
    if (pd_base + pd_idx * 4 + 4 > ctx->phys_mem_size) {
        *out_fault_error = 0;
        return false;
    }
    uint32_t *pd = (uint32_t *)(ctx->phys_memory + pd_base);
    uint32_t pd_entry = pd[pd_idx];
    if (!(pd_entry & PTE_PRESENT)) {
        *out_fault_error = ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0) | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }
    if ((access_flags & ACCESS_USER) && !(pd_entry & PTE_USER)) {
        *out_fault_error = FAULT_P | FAULT_US | ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0);
        return false;
    }
    if ((access_flags & ACCESS_WRITE) && !(pd_entry & PTE_RW)) {
        *out_fault_error = FAULT_P | FAULT_WR | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }

    uint32_t pt_base = pd_entry & ~0xFFF;
    if (pt_base + pt_idx * 4 + 4 > ctx->phys_mem_size) {
        *out_fault_error = 0;
        return false;
    }
    uint32_t *pt = (uint32_t *)(ctx->phys_memory + pt_base);
    uint32_t pt_entry = pt[pt_idx];
    if (!(pt_entry & PTE_PRESENT)) {
        *out_fault_error = ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0) | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }
    if ((access_flags & ACCESS_USER) && !(pt_entry & PTE_USER)) {
        *out_fault_error = FAULT_P | FAULT_US | ((access_flags & ACCESS_WRITE) ? FAULT_WR : 0);
        return false;
    }
    if ((access_flags & ACCESS_WRITE) && !(pt_entry & PTE_RW)) {
        *out_fault_error = FAULT_P | FAULT_WR | ((access_flags & ACCESS_USER) ? FAULT_US : 0);
        return false;
    }

    /* 3. Success: Update Accessed & Dirty Bits along path */
    pdpt[pdpt_idx] |= PTE_ACCESSED;
    pd[pd_idx]     |= PTE_ACCESSED;
    pt[pt_idx]     |= PTE_ACCESSED;
    if (access_flags & ACCESS_WRITE) {
        pt[pt_idx] |= PTE_DIRTY;
    }

    /* Combined permissions across all 3 levels */
    uint32_t comb_flags = (pdpt_entry & pd_entry & pt_entry) & (PTE_RW | PTE_USER | PTE_PRESENT);

    /* 4. Cache in Software TLB */
    uint32_t slot = ctx->tlb_rr_idx;
    ctx->tlb[slot].valid = true;
    ctx->tlb[slot].vpn = vpn;
    ctx->tlb[slot].ppn = pt_entry & ~0xFFF;
    ctx->tlb[slot].flags = comb_flags;
    ctx->tlb_rr_idx = (slot + 1) % TLB_SIZE;

    *out_hpa = (pt_entry & ~0xFFF) + off;
    return true;
}

int main(void) {
    int tests_passed = 0;
    uint64_t state_hash = 0x8badf00ddeadbeefULL;

    /* Allocate 1MB Simulated Host Physical Memory */
    mmu_ctx_t ctx;
    memset(&ctx, 0, sizeof(ctx));
    ctx.phys_mem_size = 1024 * 1024;
    ctx.phys_memory = (uint8_t *)calloc(1, ctx.phys_mem_size);
    assert(ctx.phys_memory != NULL);

    /* Setup Page Table Hierarchy at GPA 0x10000 (PDPT), 0x11000 (PD), 0x12000 (PT) */
    ctx.guest_cr3 = 0x10000;
    uint32_t *pdpt = (uint32_t *)(ctx.phys_memory + 0x10000);
    uint32_t *pd   = (uint32_t *)(ctx.phys_memory + 0x11000);
    uint32_t *pt   = (uint32_t *)(ctx.phys_memory + 0x12000);

    /* PDPT[0] -> PD (GPA 0x11000), Present | RW | User */
    pdpt[0] = 0x11000 | PTE_PRESENT | PTE_RW | PTE_USER;
    /* PD[0] -> PT (GPA 0x12000), Present | RW | User */
    pd[0]   = 0x12000 | PTE_PRESENT | PTE_RW | PTE_USER;
    /* PT[5] -> Target Physical Page 0x50000, Present | RW | User */
    pt[5]   = 0x50000 | PTE_PRESENT | PTE_RW | PTE_USER;

    uint32_t target_gva = (0 << 22) | (0 << 12) | (5 << 12) | 0x123; // GVA 0x5123
    uint32_t hpa = 0, fault = 0;

    /* Test 1: Basic 3-Level Page Walk */
    if (mmu_translate_gva(&ctx, target_gva, ACCESS_READ | ACCESS_USER, &hpa, &fault)) {
        if (hpa == 0x50123 && ctx.tlb_misses == 1) {
            tests_passed++;
            state_hash ^= (hpa * 0x100000001B3ULL);
        } else {
            printf("FAIL: Test 1 wrong HPA or stats (hpa=0x%x, misses=%u)\n", hpa, ctx.tlb_misses);
        }
    } else {
        printf("FAIL: Test 1 translation failed\n");
    }

    /* Test 2: TLB Hit Check (Same access should hit TLB directly without incrementing miss) */
    if (mmu_translate_gva(&ctx, target_gva, ACCESS_READ | ACCESS_USER, &hpa, &fault)) {
        if (hpa == 0x50123 && ctx.tlb_hits == 1 && ctx.tlb_misses == 1) {
            tests_passed++;
            state_hash ^= 0x1111222233334444ULL;
        } else {
            printf("FAIL: Test 2 TLB hit check failed (hits=%u, misses=%u)\n", ctx.tlb_hits, ctx.tlb_misses);
        }
    } else {
        printf("FAIL: Test 2 translation failed\n");
    }

    /* Test 3: Page Fault on Non-Present Page */
    uint32_t unmapped_gva = (0 << 22) | (0 << 12) | (10 << 12); // PT[10] is 0 (not present)
    if (!mmu_translate_gva(&ctx, unmapped_gva, ACCESS_READ, &hpa, &fault)) {
        if ((fault & FAULT_P) == 0) { // Fault caused by non-present page
            tests_passed++;
            state_hash ^= 0x5555666677778888ULL;
        } else {
            printf("FAIL: Test 3 wrong fault code 0x%x\n", fault);
        }
    } else {
        printf("FAIL: Test 3 should have faulted on non-present page\n");
    }

    /* Test 4: Supervisor Privilege Violation Trapping (User mode accessing supervisor page) */
    pt[6] = 0x60000 | PTE_PRESENT | PTE_RW; // PTE_USER clear -> Supervisor only
    uint32_t sup_gva = (0 << 22) | (0 << 12) | (6 << 12);
    if (!mmu_translate_gva(&ctx, sup_gva, ACCESS_READ | ACCESS_USER, &hpa, &fault)) {
        if ((fault & FAULT_P) && (fault & FAULT_US)) {
            tests_passed++;
            state_hash ^= 0x9999AAAABBBBCCCCULL;
        } else {
            printf("FAIL: Test 4 wrong fault flags 0x%x\n", fault);
        }
    } else {
        printf("FAIL: Test 4 should have trapped user access to supervisor page\n");
    }

    /* Test 5: Read-Only Write Violation Trapping */
    pt[7] = 0x70000 | PTE_PRESENT | PTE_USER; // PTE_RW clear -> Read Only
    uint32_t ro_gva = (0 << 22) | (0 << 12) | (7 << 12);
    if (!mmu_translate_gva(&ctx, ro_gva, ACCESS_WRITE | ACCESS_USER, &hpa, &fault)) {
        if ((fault & FAULT_P) && (fault & FAULT_WR)) {
            tests_passed++;
            state_hash ^= 0xDDDDEEEEFFFF0000ULL;
        } else {
            printf("FAIL: Test 5 wrong fault flags 0x%x\n", fault);
        }
    } else {
        printf("FAIL: Test 5 should have trapped write to RO page\n");
    }

    /* Test 6: Accessed and Dirty Bit Propagation */
    pt[8] = 0x80000 | PTE_PRESENT | PTE_RW | PTE_USER;
    uint32_t dirty_gva = (0 << 22) | (0 << 12) | (8 << 12);
    if (mmu_translate_gva(&ctx, dirty_gva, ACCESS_WRITE | ACCESS_USER, &hpa, &fault)) {
        if ((pt[8] & PTE_ACCESSED) && (pt[8] & PTE_DIRTY)) {
            tests_passed++;
            state_hash ^= 0x1234567890ABCDEFULL;
        } else {
            printf("FAIL: Test 6 PTE bits not set (pt[8]=0x%x)\n", pt[8]);
        }
    } else {
        printf("FAIL: Test 6 write translation failed\n");
    }

    /* Test 7: Selective INVLPG check */
    mmu_invlpg(&ctx, target_gva);
    /* Now translating target_gva should cause a TLB miss */
    uint32_t old_misses = ctx.tlb_misses;
    if (mmu_translate_gva(&ctx, target_gva, ACCESS_READ | ACCESS_USER, &hpa, &fault)) {
        if (ctx.tlb_misses == old_misses + 1) {
            tests_passed++;
            state_hash ^= 0xFEDCBA0987654321ULL;
        } else {
            printf("FAIL: Test 7 INVLPG did not invalidate TLB entry\n");
        }
    } else {
        printf("FAIL: Test 7 translation after INVLPG failed\n");
    }

    /* Test 8: Full TLB Flush on CR3 Reload */
    mmu_tlb_flush(&ctx);
    bool all_invalid = true;
    for (int i = 0; i < TLB_SIZE; i++) {
        if (ctx.tlb[i].valid) all_invalid = false;
    }
    if (all_invalid) {
        tests_passed++;
        state_hash ^= 0x4242424242424242ULL;
    } else {
        printf("FAIL: Test 8 mmu_tlb_flush did not clear all entries\n");
    }

    free(ctx.phys_memory);

    if (tests_passed != 8) {
        printf("FAIL: Not all tests passed (%d/8)\n", tests_passed);
        return 1;
    }

    printf("Verification SUCCESS! Dynamic State Hash computed over %d MMU verification tests.\n", tests_passed);
    printf("cyberbench{vmm_shadow_mmu_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
