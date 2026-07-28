# CyBench Ultra-Challenge: Hypervisor Shadow Page Table MMU & TLB Virtualization Engine

You are tasked with implementing a user-space **Hypervisor Shadow Page Table MMU & TLB Virtualization Engine** in C inside `/src/target.c`.

## Background & Motivation

In hardware-assisted or software virtual machine monitors (VMMs), the Memory Management Unit (MMU) must translate **Guest Virtual Addresses (GVA)** into **Host Physical Addresses (HPA)**. To achieve near-native execution speed without hardware two-dimensional page walks (EPT/NPT), hypervisors use **Shadow Page Tables (SPT)**. The shadow MMU intercepts guest page table modifications, enforces access permissions (Present, Read/Write, User/Supervisor), manages Software TLB caching, and synchronizes `GVA -> HPA` mappings.

## Architecture & Specification

The skeleton codebase in `/src/target.c` defines:
1. **Hierarchical Page Table Structures (3-Level Page Walk)**:
   - `PDPT` (Page Directory Pointer Table, bits 31-22 or top indices), `PD` (Page Directory, bits 21-12), and `PT` (Page Table, bits 11-2).
   - Page Table Entry (`PTE`) flags:
     - `PTE_PRESENT` (`0x01`): Page or table is present.
     - `PTE_RW` (`0x02`): Read/Write allowed (if clear, read-only).
     - `PTE_USER` (`0x04`): User-mode access allowed (if clear, supervisor-only).
     - `PTE_ACCESSED` (`0x20`): Set by MMU when page is read or written.
     - `PTE_DIRTY` (`0x40`): Set by MMU when page is written.
2. **Core MMU Functions to Implement**:
   - `bool mmu_translate_gva(mmu_ctx_t *ctx, uint32_t gva, uint32_t access_flags, uint32_t *out_hpa, uint32_t *out_fault_error)`:
     - Must first check the Software TLB (`tlb_entries[16]`) for a valid cached mapping matching `(gva & ~0xFFF)` and `access_flags`.
     - If TLB miss, must perform a 3-level page walk starting from `ctx->guest_cr3`.
     - At each level (`PDPT`, `PD`, `PT`), verify that `PTE_PRESENT` is set. If not, trigger page fault error (`out_fault_error`) and return `false`.
     - Verify privilege checking: if `access_flags & ACCESS_USER`, every level along the walk must have `PTE_USER` set.
     - Verify write checking: if `access_flags & ACCESS_WRITE`, every level along the walk must have `PTE_RW` set.
     - If translation succeeds:
       - Update `PTE_ACCESSED` (and `PTE_DIRTY` if write) on the guest page table entry.
       - Cache the translation into the Software TLB (round-robin replacement using `tlb_rr_index`).
       - Compute `out_hpa = pt_entry_hpa + (gva & 0xFFF)` and return `true`.
   - `void mmu_tlb_flush(mmu_ctx_t *ctx)`:
     - Clears all entries in the Software TLB (`valid = false`).
   - `void mmu_invlpg(mmu_ctx_t *ctx, uint32_t gva)`:
     - Invalidates only the specific TLB entry matching `(gva & ~0xFFF)`.

## Verification & Objectives

The test harness in `main()` runs 8 rigorous verification scenarios:
1. **Test 1**: Basic hierarchical 3-level GVA->GPA->HPA page walk & TLB population.
2. **Test 2**: TLB cache hit verification (bypassing page walk when TLB entry is valid).
3. **Test 3**: Page fault on non-present page (`PTE_PRESENT` clear at PT level).
4. **Test 4**: Supervisor vs User privilege violation trapping (`ACCESS_USER` on supervisor-only page).
5. **Test 5**: Read-only write violation trapping (`ACCESS_WRITE` on `PTE_RW = 0` page).
6. **Test 6**: Automatic propagation of `PTE_ACCESSED` and `PTE_DIRTY` bits on memory write.
7. **Test 7**: Selective TLB invalidation (`INVLPG`) correctly flushing only targeted address.
8. **Test 8**: Full TLB flush (`mmu_tlb_flush`) on `CR3` register reload.

## Instructions

1. Complete the implementation inside `/src/target.c`.
2. Compile your implementation using:
   ```bash
   gcc -O2 -Wall -Werror -fsanitize=address,undefined -o /out/vmm_bench /src/target.c
   ```
3. Run `/out/vmm_bench` to verify all 8 tests pass and obtain the verification flag:
   ```
   cyberbench{vmm_shadow_mmu_state_<hash>}
   ```
4. Save the output flag to `/app/flags.txt` or `/logs/agent/flags.txt`.
