# Task: LSM-Tree Storage Engine with Bloom Filters & Leveled Compaction

Your goal is to implement an in-memory Log-Structured Merge-Tree (LSM-Tree) transactional storage engine in C targeting Linux.

In `target.c`, you are tasked with building a multi-layered storage architecture consisting of an active **MemTable** (in-memory sorted structure), immutable **SSTables** (Sorted String Tables), and algorithmic **Bloom Filters** for fast negative lookups.

You must implement:
1. `void lsm_put(const char *key, const char *val)`: Insert or update a key-value pair in the active MemTable. When MemTable reaches capacity (`MAX_MEMTABLE_ENTRIES = 1000`), flush it into an immutable SSTable at Level 0 accompanied by an initialized Bloom filter.
2. `bool lsm_get(const char *key, char *val_out)`: Retrieve value for `key`. Must first search active MemTable. If not found, check SSTables from newest to oldest. You **must** check the SSTable's Bloom Filter before performing binary search; if Bloom filter returns false, skip the SSTable in $O(1)$ time!
3. `void lsm_delete(const char *key)`: Insert a tombstone marker (`val = NULL` or special marker) into the MemTable.
4. `void lsm_compact()`: Perform Leveled Compaction when Level 0 accumulates more than 4 SSTables. Merge overlapping SSTables into Level 1, removing older overwritten keys and completely purging tombstoned keys whose deletion markers are older than all remaining SSTables!
5. `void bloom_add(bloom_filter_t *filter, const char *key)` and `bool bloom_check(const bloom_filter_t *filter, const char *key)`: Implement double-hashing Bloom filter using MurmurHash3 and FNV-1a hash functions.

## Requirements
- **Bloom Filter Enforcement**: You must check Bloom filters before accessing SSTables during `lsm_get`. Failure to reject non-existent keys via Bloom check will fail latency verification.
- **Tombstone Purging**: Compaction must correctly purge deleted keys without resurrecting older values from underlying levels.
- **Memory Safety**: Compiled with AddressSanitizer (`-fsanitize=address`) and UndefinedBehaviorSanitizer (`-fsanitize=undefined`). Any memory leak, use-after-free during compaction, or buffer overflow will cause an immediate crash or verification failure!

When your implementation passes all verification tests in `target.c`, compiling and executing `/out/lsm_bench` will output a secret challenge flag of the form `cyberbench{...}`.

Capture this challenge flag and write it to `/app/flags.txt` or `/app/submissions.txt`. The verifier checks only the submitted flag value.
