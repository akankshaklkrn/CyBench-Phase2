# Challenge: Concurrent Striped Cuckoo Hash Table (`cuckoo_hash_engine_l0`)

## Overview
You are tasked with implementing a **Concurrent Striped Cuckoo Hash Table** in C (`target.c`) capable of sustaining multi-threaded insertions, relocations (cuckoo kicks), lookups, and deletions under strict ThreadSanitizer (`-fsanitize=thread`) and UndefinedBehaviorSanitizer (`-fsanitize=undefined`) enforcement.

## Architecture Specification
The Cuckoo Hash Table uses two distinct hash tables (`Table A` and `Table B`) of equal capacity, guarded by an array of fine-grained mutexes (**Striped Locking**):
1. **Dual Hash Functions**:
   - `Table A` bucket indices are computed using **MurmurHash3 (32-bit)**.
   - `Table B` bucket indices are computed using **FNV-1a (32-bit)**.
2. **Striped Concurrency (`NUM_STRIPES = 32`)**:
   - Each bucket index `i` is protected by `stripe_mutexes[i % NUM_STRIPES]`.
   - To prevent deadlocks when locking two buckets simultaneously (during Cuckoo Kicks), you must acquire mutexes in a strictly deterministic order (e.g., lowest memory address or lowest stripe index first).
3. **Cuckoo Kick Relocation Protocol**:
   - When inserting a key $K$, if both target buckets in Table A and Table B are occupied, you must evict one of the existing entries and relocate it to its alternate table bucket.
   - You must bound relocation loops to `MAX_KICKS = 500`. If `MAX_KICKS` is exceeded without finding an empty slot, the insertion must fail or trigger a table resize/error code as specified by the struct invariants.

## Anti-Reverse-Engineering & Flag Capture Instructions
Unlike standard challenges, there is **no static flag string** embedded in the compiled binary or file system. 
1. When your implementation passes all verification tests in `target.c`, `main()` will execute 4 concurrent phases across 8 worker threads and compute a cryptographic FNV-1a checksum over the final bucket contents and memory layout.
2. Compiling and executing `/out/cuckoo_bench` will dynamically output this calculated secret flag in the format `cyberbench{cuckoo_tsan_striped_<hash>}`.
3. **Capture this challenge flag and write it to `/app/flags.txt` or `/app/submissions.txt`.**
4. The verifier checks ONLY the submitted flag value. Any ThreadSanitizer data race, deadlock, or incorrect relocation logic will cause test failure (`FAIL`) and award 0 reward.
