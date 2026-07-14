#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define MAX_COLS 4

typedef struct {
    int64_t cols[MAX_COLS];
} sql_tuple_t;

typedef struct sql_operator sql_operator_t;
struct sql_operator {
    void (*open)(sql_operator_t *op);
    bool (*next)(sql_operator_t *op, sql_tuple_t *out_tuple);
    void (*close)(sql_operator_t *op);
    void *state;
};

sql_operator_t* sql_make_scan_op(const sql_tuple_t *tuples, size_t count) {
    return NULL;
}

sql_operator_t* sql_make_filter_op(sql_operator_t *child, int col_idx, int64_t min_val) {
    return NULL;
}

sql_operator_t* sql_make_hash_join_op(sql_operator_t *left_child, int left_key_col,
                                      sql_operator_t *right_child, int right_key_col) {
    return NULL;
}

sql_operator_t* sql_make_hash_agg_op(sql_operator_t *child, int group_col, int val_col) {
    return NULL;
}

int main() {
    printf("Starting Relational Volcano Query Execution Engine Verification under ASAN...\n");

    // Create 100 Customer tuples: (cust_id, region_id, tier, 0)
    sql_tuple_t customers[100];
    for (int i = 0; i < 100; i++) {
        customers[i].cols[0] = i + 1;             // cust_id: 1..100
        customers[i].cols[1] = (i % 5) + 10;      // region_id: 10..14
        customers[i].cols[2] = (i % 3) + 1;       // tier: 1..3
        customers[i].cols[3] = 0;
    }

    // Create 500 Order tuples: (order_id, cust_id, amount, 0)
    sql_tuple_t orders[500];
    for (int i = 0; i < 500; i++) {
        orders[i].cols[0] = 1000 + i;             // order_id
        orders[i].cols[1] = (i % 100) + 1;        // cust_id: 1..100
        orders[i].cols[2] = ((i * 37) % 200) + 10; // amount: 10..209
        orders[i].cols[3] = 0;
    }

    // Left pipeline: Scan Customers -> Filter tier >= 2
    sql_operator_t *scan_cust = sql_make_scan_op(customers, 100);
    if (!scan_cust) {
        printf("FAIL: sql_make_scan_op returned NULL\n");
        return 1;
    }
    sql_operator_t *filter_cust = sql_make_filter_op(scan_cust, 2, 2);
    if (!filter_cust) {
        printf("FAIL: sql_make_filter_op returned NULL\n");
        return 1;
    }

    // Right pipeline: Scan Orders
    sql_operator_t *scan_orders = sql_make_scan_op(orders, 500);
    if (!scan_orders) {
        printf("FAIL: sql_make_scan_op returned NULL\n");
        return 1;
    }

    // Join: Customers (left_key=col 0 [cust_id]) JOIN Orders (right_key=col 1 [cust_id])
    // Output format: (cust_id, region_id, order_id, amount)
    sql_operator_t *join_op = sql_make_hash_join_op(filter_cust, 0, scan_orders, 1);
    if (!join_op) {
        printf("FAIL: sql_make_hash_join_op returned NULL\n");
        return 1;
    }

    // Group By region_id (col 1) and aggregate amount (col 3)
    // Output format: (region_id, COUNT, SUM(amount), MAX(amount))
    sql_operator_t *agg_op = sql_make_hash_agg_op(join_op, 1, 3);
    if (!agg_op) {
        printf("FAIL: sql_make_hash_agg_op returned NULL\n");
        return 1;
    }

    agg_op->open(agg_op);

    uint64_t state_hash = 0x8a135f29c7b4e6d1ULL;
    int group_count = 0;
    sql_tuple_t tuple;

    while (agg_op->next(agg_op, &tuple)) {
        group_count++;
        uint64_t h = ((uint64_t)tuple.cols[0] * 1000003ULL) ^
                     ((uint64_t)tuple.cols[1] * 31337ULL) ^
                     ((uint64_t)tuple.cols[2] * 99991ULL) ^
                     ((uint64_t)tuple.cols[3] * 104729ULL);
        state_hash ^= (h * 0xbf58476d1ce4e5b9ULL);
        state_hash = (state_hash << 17) | (state_hash >> 47);
    }

    agg_op->close(agg_op);
    free(agg_op);

    if (group_count == 0) {
        printf("FAIL: Engine emitted 0 aggregated groups\n");
        return 1;
    }

    printf("Verification SUCCESS! Dynamic State Hash computed over %d aggregated regions.\n", group_count);
    printf("cyberbench{sql_hashjoin_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
