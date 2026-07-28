# Challenge: Multi-Version Concurrency Control (MVCC) Storage Engine with GC (`mvcc_storage_engine_l0`)

You are tasked with building a Multi-Version Concurrency Control (MVCC) key-value engine in standard C. The engine implements timestamp-ordered version chains for each key, supports Snapshot Isolation reads across historical transaction horizons, and performs Garbage Collection (GC) vacuum sweeps to reclaim obsolete version nodes without memory leaks under AddressSanitizer.

## Architecture & Rules

### 1. Version Chain Layout (`mvcc_version_t`)
Every key in the database points to a linked list (version chain) ordered from newest version to oldest version:
```c
typedef struct mvcc_version {
    uint64_t create_ts;
    uint64_t expire_ts; // INF_TS (UINT64_MAX) if currently active
    uint64_t value;
    struct mvcc_version *next;
} mvcc_version_t;
```

### 2. Snapshot Isolation Visibility Rules
When a transaction reads key `key_id` at snapshot timestamp `read_ts`:
- Traverse the version chain starting from the head.
- A version `v` is visible if and only if:
  `v->create_ts <= read_ts` AND `v->expire_ts > read_ts`
- If a visible version is found, set `*out_val = v->value` and return `true`.
- If no visible version exists at `read_ts`, return `false`.

### 3. Transactional Write (`mvcc_put`)
When writing `(key_id, value)` at commit timestamp `commit_ts`:
- If an existing head version `curr` is active (`curr->expire_ts == INF_TS`), set `curr->expire_ts = commit_ts`.
- Allocate a new `mvcc_version_t` node with `create_ts = commit_ts`, `expire_ts = INF_TS`, and `value = value`.
- Prepend this new version node to the head of `key_id`'s version chain.

### 4. Garbage Collection (GC) Vacuum Sweep (`mvcc_gc_vacuum`)
To prevent unbounded memory growth, the database periodically executes `mvcc_gc_vacuum(mvcc_db_t *db, uint64_t min_active_ts)`:
- Any version node whose `expire_ts <= min_active_ts` is completely obsolete (no transaction at `read_ts >= min_active_ts` can ever see it).
- Traverse each key's version chain. If a node has `expire_ts <= min_active_ts`, unlink and `free()` that node and all subsequent older nodes in the chain.
- Increment `db->stats.gc_reclaimed_nodes` by the number of version nodes freed.
- IMPORTANT: You must not leak memory or free active/visible versions. AddressSanitizer checks every allocation.

### 5. Sanitization & Dynamic Flag Generation
- The binary is compiled under **AddressSanitizer (`-fsanitize=address,undefined`)**.
- After executing 1,000 interleaved read/write operations and GC vacuum sweeps, the test harness asserts 0 AddressSanitizer leaks and calculates an order-independent XOR checksum over all surviving version timestamps and GC statistics to output `cyberbench{mvcc_gc_snapshot_<hash>}`.

## Functions to Implement in `target.c`
```c
bool mvcc_init(mvcc_db_t *db, int num_keys);
void mvcc_destroy(mvcc_db_t *db);
bool mvcc_put(mvcc_db_t *db, int key_id, uint64_t value, uint64_t commit_ts);
bool mvcc_get(mvcc_db_t *db, int key_id, uint64_t read_ts, uint64_t *out_val);
uint64_t mvcc_gc_vacuum(mvcc_db_t *db, uint64_t min_active_ts);
```
