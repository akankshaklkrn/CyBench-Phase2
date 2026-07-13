#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>
#include <sys/stat.h>
#include <sys/types.h>

#define BLOOM_BITS 1024
#define MAX_MEMTABLE_ENTRIES 1000
#define MAX_SSTABLES 10
#define KEY_LEN 32
#define VAL_LEN 64

typedef struct {
    uint8_t bits[BLOOM_BITS / 8];
} bloom_filter_t;

typedef struct {
    char key[KEY_LEN];
    char val[VAL_LEN];
    bool is_tombstone;
} kv_entry_t;

typedef struct {
    kv_entry_t entries[MAX_MEMTABLE_ENTRIES];
    int count;
    bloom_filter_t bloom;
} sstable_t;

static kv_entry_t memtable[MAX_MEMTABLE_ENTRIES];
static int memtable_count = 0;
static sstable_t sstables[MAX_SSTABLES];
static int sstable_count = 0;

// TODO: Implement Bloom filter add and check using FNV-1a and MurmurHash3
void bloom_add(bloom_filter_t *filter, const char *key) {
    // Set two bits corresponding to hash values
}

bool bloom_check(const bloom_filter_t *filter, const char *key) {
    // Return true only if both hash bits are set
    return false;
}

// TODO: Implement MemTable insertion and flushing to SSTable
void lsm_put(const char *key, const char *val) {
    // Insert into memtable; flush to new sstable with bloom filter if capacity reached
}

// TODO: Implement LSM lookup with Bloom filter negative read rejection
bool lsm_get(const char *key, char *val_out) {
    // Check memtable, then iterate sstables (MUST check bloom_check before searching SSTable)
    return false;
}

// TODO: Implement deletion (tombstone insertion)
void lsm_delete(const char *key) {
    // Put key with is_tombstone=true
}

// TODO: Implement Leveled Compaction with tombstone purging
void lsm_compact() {
    // Merge overlapping SSTables, discard overwritten keys, purge obsolete tombstones
}

int main() {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("Starting LSM-Tree Storage Engine with Bloom Filters & Compaction Test...\n");

    memset(memtable, 0, sizeof(memtable));
    memset(sstables, 0, sizeof(sstables));
    memtable_count = 0;
    sstable_count = 0;

    printf("Executing Phase 1: High-Frequency Insertion & MemTable Flushing...\n");
    char k[KEY_LEN], v[VAL_LEN];
    for (int i = 0; i < 2500; i++) {
        snprintf(k, KEY_LEN, "user_key_%d", i);
        snprintf(v, VAL_LEN, "payload_value_%d", i);
        lsm_put(k, v);
    }
    
    if (sstable_count < 2) {
        printf("FAIL: MemTable failed to flush into SSTables! SSTable count: %d\n", sstable_count);
        return 1;
    }

    printf("Executing Phase 2: Bloom Filter Negative Lookups...\n");
    char val_out[VAL_LEN];
    if (lsm_get("non_existent_key_999999", val_out)) {
        printf("FAIL: Found non-existent key! Bloom filter or search logic is broken.\n");
        return 1;
    }

    printf("Executing Phase 3: Tombstone Deletions & Leveled Compaction...\n");
    lsm_delete("user_key_100");
    lsm_delete("user_key_500");
    lsm_compact();
    
    if (lsm_get("user_key_100", val_out)) {
        printf("FAIL: Tombstoned key 'user_key_100' resurrected after compaction! Got: %s\n", val_out);
        return 1;
    }
    
    if (!lsm_get("user_key_1000", val_out) || strcmp(val_out, "payload_value_1000") != 0) {
        printf("FAIL: Valid key 'user_key_1000' lost or corrupted after compaction! Got: %s\n", val_out);
        return 1;
    }

    printf("PASS: All MemTable, SSTable, Bloom filter, and compaction tests passed.\n");
    printf("FLAG: cyberbench{lsm_tree_compaction_success_8f3a92b}\n");
    
    mkdir("/app", 0755);
    FILE *flag_file = fopen("/app/flags.txt", "w");
    if (flag_file) {
        fprintf(flag_file, "cyberbench{lsm_tree_compaction_success_8f3a92b}\n");
        fclose(flag_file);
    }
    return 0;
}
