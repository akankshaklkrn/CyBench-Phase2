#!/bin/bash
set -e

if mkdir -p /src 2>/dev/null && [ -w "/src" ]; then
    TARGET_PATH="/src/target.c"
else
    mkdir -p environment 2>/dev/null || true
    TARGET_PATH="environment/target.c"
fi

cat << 'EOF' > "$TARGET_PATH"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define MAX_FRAMES 64
#define TLB_ENTRIES 16
#define NUM_ACCESSES 10000

#define PTE_PRESENT  0x1
#define PTE_WRITE    0x2
#define PTE_DIRTY    0x4
#define PTE_ACCESSED 0x8

typedef struct {
    uint32_t pfn;
    uint32_t flags;
} pte_t;

typedef struct {
    pte_t entries[1024];
} page_table_t;

typedef struct {
    page_table_t *tables[1024];
} page_dir_t;

typedef struct {
    bool valid;
    uint32_t vpn;
    uint32_t pfn;
    uint32_t flags;
} tlb_entry_t;

typedef struct {
    uint32_t owner_va;
    pte_t *owner_pte;
    bool is_allocated;
} frame_desc_t;

typedef struct {
    uint64_t page_faults;
    uint64_t tlb_hits;
    uint64_t tlb_misses;
    uint64_t evicted_pages;
    uint64_t dirty_evictions;
} vm_stats_t;

typedef struct {
    page_dir_t *pgdir;
    tlb_entry_t tlb[TLB_ENTRIES];
    frame_desc_t frames[MAX_FRAMES];
    uint32_t clock_hand;
    vm_stats_t stats;
} vm_engine_t;

bool vm_init(vm_engine_t *vm) {
    vm->pgdir = (page_dir_t *)calloc(1, sizeof(page_dir_t));
    if (!vm->pgdir) return false;
    for (int i = 0; i < TLB_ENTRIES; i++) {
        vm->tlb[i].valid = false;
    }
    for (int i = 0; i < MAX_FRAMES; i++) {
        vm->frames[i].is_allocated = false;
        vm->frames[i].owner_va = 0;
        vm->frames[i].owner_pte = NULL;
    }
    vm->clock_hand = 0;
    memset(&vm->stats, 0, sizeof(vm->stats));
    return true;
}

void vm_destroy(vm_engine_t *vm) {
    if (!vm->pgdir) return;
    for (int i = 0; i < 1024; i++) {
        if (vm->pgdir->tables[i]) {
            free(vm->pgdir->tables[i]);
            vm->pgdir->tables[i] = NULL;
        }
    }
    free(vm->pgdir);
    vm->pgdir = NULL;
}

void tlb_flush(vm_engine_t *vm, uint32_t va) {
    uint32_t vpn = va & ~0xFFF;
    uint32_t slot = (va >> 12) % TLB_ENTRIES;
    if (vm->tlb[slot].valid && vm->tlb[slot].vpn == vpn) {
        vm->tlb[slot].valid = false;
    }
}

bool vm_access(vm_engine_t *vm, uint32_t va, bool is_write, uint32_t *out_pfn) {
    uint32_t vpn = va & ~0xFFF;
    uint32_t slot = (va >> 12) % TLB_ENTRIES;
    if (vm->tlb[slot].valid && vm->tlb[slot].vpn == vpn) {
        vm->stats.tlb_hits++;
        uint32_t pfn = vm->tlb[slot].pfn;
        pte_t *pte = &vm->pgdir->tables[va >> 22]->entries[(va >> 12) & 0x3FF];
        pte->flags |= PTE_ACCESSED;
        if (is_write) pte->flags |= (PTE_WRITE | PTE_DIRTY);
        vm->tlb[slot].flags = pte->flags;
        *out_pfn = pfn;
        return true;
    }
    vm->stats.tlb_misses++;
    
    uint32_t pdi = va >> 22;
    uint32_t pti = (va >> 12) & 0x3FF;
    if (vm->pgdir->tables[pdi] == NULL) {
        vm->pgdir->tables[pdi] = (page_table_t *)calloc(1, sizeof(page_table_t));
        if (!vm->pgdir->tables[pdi]) return false;
    }
    pte_t *pte = &vm->pgdir->tables[pdi]->entries[pti];
    
    if (!(pte->flags & PTE_PRESENT)) {
        vm->stats.page_faults++;
        int victim_frame = -1;
        for (int i = 0; i < MAX_FRAMES; i++) {
            if (!vm->frames[i].is_allocated) {
                victim_frame = i;
                break;
            }
        }
        if (victim_frame == -1) {
            while (true) {
                int hand = vm->clock_hand;
                frame_desc_t *f = &vm->frames[hand];
                if (f->owner_pte && (f->owner_pte->flags & PTE_ACCESSED)) {
                    f->owner_pte->flags &= ~PTE_ACCESSED;
                    vm->clock_hand = (hand + 1) % MAX_FRAMES;
                } else {
                    victim_frame = hand;
                    break;
                }
            }
            frame_desc_t *vic = &vm->frames[victim_frame];
            if (vic->owner_pte) {
                if (vic->owner_pte->flags & PTE_DIRTY) {
                    vm->stats.dirty_evictions++;
                }
                vic->owner_pte->flags &= ~(PTE_PRESENT | PTE_DIRTY | PTE_ACCESSED);
                tlb_flush(vm, vic->owner_va);
                vm->stats.evicted_pages++;
                vic->owner_pte = NULL;
            }
            vm->clock_hand = (victim_frame + 1) % MAX_FRAMES;
        }
        pte->pfn = victim_frame + 100;
        pte->flags = PTE_PRESENT;
        vm->frames[victim_frame].is_allocated = true;
        vm->frames[victim_frame].owner_va = vpn;
        vm->frames[victim_frame].owner_pte = pte;
    }
    
    pte->flags |= PTE_ACCESSED;
    if (is_write) pte->flags |= (PTE_WRITE | PTE_DIRTY);
    vm->tlb[slot].valid = true;
    vm->tlb[slot].vpn = vpn;
    vm->tlb[slot].pfn = pte->pfn;
    vm->tlb[slot].flags = pte->flags;
    *out_pfn = pte->pfn;
    return true;
}

int main() {
    printf("Starting VM Paging & TLB Eviction Engine Verification under ASAN...\n");
    
    vm_engine_t vm;
    memset(&vm, 0, sizeof(vm));
    if (!vm_init(&vm)) {
        printf("FAIL: vm_init returned false.\n");
        return 1;
    }
    
    printf("Executing Phase 1: Demand paging fault allocation & TLB hit check...\n");
    uint32_t pfn1 = 0, pfn2 = 0;
    if (!vm_access(&vm, 0x00400000, true, &pfn1)) {
        printf("FAIL: Phase 1 demand page fault failed.\n");
        vm_destroy(&vm);
        return 1;
    }
    if (!vm_access(&vm, 0x00400004, false, &pfn2) || pfn1 != pfn2) {
        printf("FAIL: Phase 1 same-page access returned different PFN.\n");
        vm_destroy(&vm);
        return 1;
    }
    if (vm.stats.page_faults != 1 || vm.stats.tlb_hits != 1) {
        printf("FAIL: Expected 1 fault and 1 TLB hit, got faults=%llu hits=%llu.\n",
               (unsigned long long)vm.stats.page_faults, (unsigned long long)vm.stats.tlb_hits);
        vm_destroy(&vm);
        return 1;
    }
    
    printf("Executing Phase 2: High-Volume Page Thrashing & Clock Replacement...\n");
    for (int i = 0; i < NUM_ACCESSES; i++) {
        uint32_t page_num = (i * 7) % 128;
        uint32_t va = 0x10000000 + (page_num * 4096) + (i % 64);
        bool write = (i % 3 == 0);
        uint32_t out_pfn = 0;
        if (!vm_access(&vm, va, write, &out_pfn)) {
            printf("FAIL: vm_access failed at iteration %d.\n", i);
            vm_destroy(&vm);
            return 1;
        }
    }
    
    if (vm.stats.evicted_pages == 0 || vm.stats.dirty_evictions == 0) {
        printf("FAIL: Eviction policy did not trigger dirty page evictions.\n");
        vm_destroy(&vm);
        return 1;
    }
    
    uint64_t state_hash = 0x9f8e7d6c5b4a3210ULL;
    state_hash ^= vm.stats.page_faults * 0x100000001b3ULL;
    state_hash ^= vm.stats.tlb_hits * 0xc4ceb9fe1a85ec53ULL;
    state_hash ^= vm.stats.tlb_misses * 0x9e3779b97f4a7c15ULL;
    state_hash ^= vm.stats.evicted_pages * 0xbf58476d1ce4e5b9ULL;
    state_hash ^= vm.stats.dirty_evictions * 0xd6e8feb86659fd93ULL;
    
    for (int i = 0; i < MAX_FRAMES; i++) {
        if (vm.frames[i].is_allocated) {
            uint64_t fh = vm.frames[i].owner_va * 0x100000001b3ULL;
            fh ^= i * 0xc4ceb9fe1a85ec53ULL;
            if (vm.frames[i].owner_pte) {
                fh ^= vm.frames[i].owner_pte->flags * 0x9e3779b97f4a7c15ULL;
            }
            state_hash ^= fh;
        }
    }
    
    printf("Verification SUCCESS! Dynamic State Hash computed.\n");
    printf("cyberbench{vm_paging_tlb_%016lx}\n", (unsigned long)state_hash);
    
    vm_destroy(&vm);
    return 0;
}
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -pthread -fsanitize=address,undefined -o "$OUT_DIR/vm_bench" "$TARGET_PATH"
"$OUT_DIR/vm_bench" > /tmp/out.log
FLAG=$(grep -o "cyberbench{[^}]*}" /tmp/out.log || true)

if [ -n "$FLAG" ]; then
    if [ -d "/app" ] && [ -w "/app" ]; then
        echo "$FLAG" > /app/flags.txt
    else
        echo "$FLAG" > flags.txt
    fi
    echo "Oracle successfully generated dynamic flag: $FLAG"
else
    echo "Oracle failed to generate flag!"
    cat /tmp/out.log
    exit 1
fi
