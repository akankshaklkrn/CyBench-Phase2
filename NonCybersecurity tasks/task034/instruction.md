# Challenge: Virtual Memory Paging & TLB Eviction Engine (`vm_paging_engine_l0`)

You are tasked with building a high-performance Operating System Virtual Memory Paging Engine in C. The engine manages a 2-level hierarchical page table, a set-associative Translation Lookaside Buffer (TLB), demand paging physical frame allocation, and the Second-Chance Clock page replacement eviction algorithm.

## Technical Specifications

### 1. Address Layout & Permission Flags
- **Virtual Address Layout (32-bit)**:
  - Page Directory Index (`PDI`): Bits [31:22] (top 10 bits, 1024 entries).
  - Page Table Index (`PTI`): Bits [21:12] (next 10 bits, 1024 entries).
  - Page Offset (`OFFSET`): Bits [11:0] (lowest 12 bits, 4096 bytes per page).
- **Page Table Entry (PTE) Flags**:
  - `PTE_PRESENT = 0x1` (bit 0): Page frame is currently mapped in physical memory.
  - `PTE_WRITE   = 0x2` (bit 1): Page allows write access.
  - `PTE_DIRTY   = 0x4` (bit 2): Page has been modified since being mapped.
  - `PTE_ACCESSED= 0x8` (bit 3): Page has been read or written recently.

### 2. Physical Frame Pool & Second-Chance Clock Eviction
- The physical memory pool has `MAX_FRAMES = 64` page frames.
- Each allocated frame tracks its mapped virtual page (`owner_va`) and pointer to the owner `pte_t *owner_pte`.
- When allocating a frame for a demand page fault:
  1. If the pool has free frames (`num_frames < MAX_FRAMES`), allocate the next free frame.
  2. If all `MAX_FRAMES` are occupied, run the **Second-Chance Clock Eviction** algorithm starting at `clock_hand`:
     - Inspect frame at `clock_hand`:
       - If `owner_pte->flags & PTE_ACCESSED` is set, clear the `PTE_ACCESSED` flag and advance `clock_hand = (clock_hand + 1) % MAX_FRAMES`.
       - If `owner_pte->flags & PTE_ACCESSED` is 0, select this frame for eviction!
     - Eviction steps:
       - If `owner_pte->flags & PTE_DIRTY` is set, increment `stats.dirty_evictions`.
       - Clear `PTE_PRESENT`, `PTE_DIRTY`, and `PTE_ACCESSED` on `owner_pte`.
       - Invalidate any TLB cache entry matching `owner_va`.
       - Increment `stats.evicted_pages`.
       - Reclaim this frame for the new page fault and advance `clock_hand = (clock_hand + 1) % MAX_FRAMES`.

### 3. Translation Lookaside Buffer (TLB)
- Implement a direct-mapped TLB cache with `TLB_ENTRIES = 16` slots (`slot = (va >> 12) % TLB_ENTRIES`).
- Every TLB slot stores `valid`, `virtual_page` (`va & ~0xFFF`), `pfn`, and `flags`.
- On memory access (`vm_read` / `vm_write`):
  - Check TLB slot: If valid and matches `virtual_page`, increment `stats.tlb_hits`.
  - If TLB miss, perform Page Table walk. Increment `stats.tlb_misses`.

### 4. Page Fault Handling (`vm_access`)
- If PTE is not present (`!(pte->flags & PTE_PRESENT)`), increment `stats.page_faults`, allocate a physical frame (evicting if necessary), set `pte->pfn = frame_pfn`, and mark `PTE_PRESENT`.
- On read access: Set `PTE_ACCESSED`.
- On write access: Set `PTE_ACCESSED | PTE_WRITE | PTE_DIRTY`.
- Update the TLB entry for this virtual page.

### 5. Sanitization & Dynamic Flag Emission
- Compiled under **AddressSanitizer (`-fsanitize=address,undefined`)**.
- After executing 10,000 virtual memory operations, the test harness verifies memory safety and computes an order-independent XOR checksum over all surviving active page table mappings and eviction statistics to output `cyberbench{vm_paging_tlb_<hash>}`.

## Functions to Implement in `target.c`
```c
bool vm_init(vm_engine_t *vm);
void vm_destroy(vm_engine_t *vm);
bool vm_access(vm_engine_t *vm, uint32_t va, bool is_write, uint32_t *out_pfn);
void tlb_flush(vm_engine_t *vm, uint32_t va);
```
