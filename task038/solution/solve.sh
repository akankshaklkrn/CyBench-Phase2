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

#define MAX_COLS 4
#define HASH_BUCKETS 1024

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

/* 1. Scan Operator */
typedef struct {
    const sql_tuple_t *tuples;
    size_t count;
    size_t curr_idx;
} scan_state_t;

static void scan_open(sql_operator_t *op) {
    scan_state_t *st = (scan_state_t *)op->state;
    st->curr_idx = 0;
}

static bool scan_next(sql_operator_t *op, sql_tuple_t *out_tuple) {
    scan_state_t *st = (scan_state_t *)op->state;
    if (st->curr_idx < st->count) {
        *out_tuple = st->tuples[st->curr_idx++];
        return true;
    }
    return false;
}

static void scan_close(sql_operator_t *op) {
    free(op->state);
}

sql_operator_t* sql_make_scan_op(const sql_tuple_t *tuples, size_t count) {
    sql_operator_t *op = (sql_operator_t *)malloc(sizeof(sql_operator_t));
    scan_state_t *st = (scan_state_t *)malloc(sizeof(scan_state_t));
    st->tuples = tuples;
    st->count = count;
    st->curr_idx = 0;
    op->open = scan_open;
    op->next = scan_next;
    op->close = scan_close;
    op->state = st;
    return op;
}

/* 2. Filter Operator */
typedef struct {
    sql_operator_t *child;
    int col_idx;
    int64_t min_val;
} filter_state_t;

static void filter_open(sql_operator_t *op) {
    filter_state_t *st = (filter_state_t *)op->state;
    st->child->open(st->child);
}

static bool filter_next(sql_operator_t *op, sql_tuple_t *out_tuple) {
    filter_state_t *st = (filter_state_t *)op->state;
    sql_tuple_t t;
    while (st->child->next(st->child, &t)) {
        if (t.cols[st->col_idx] >= st->min_val) {
            *out_tuple = t;
            return true;
        }
    }
    return false;
}

static void filter_close(sql_operator_t *op) {
    filter_state_t *st = (filter_state_t *)op->state;
    st->child->close(st->child);
    free(st->child);
    free(op->state);
}

sql_operator_t* sql_make_filter_op(sql_operator_t *child, int col_idx, int64_t min_val) {
    sql_operator_t *op = (sql_operator_t *)malloc(sizeof(sql_operator_t));
    filter_state_t *st = (filter_state_t *)malloc(sizeof(filter_state_t));
    st->child = child;
    st->col_idx = col_idx;
    st->min_val = min_val;
    op->open = filter_open;
    op->next = filter_next;
    op->close = filter_close;
    op->state = st;
    return op;
}

/* 3. Hash Join Operator */
typedef struct hash_node {
    sql_tuple_t tuple;
    struct hash_node *next;
} hash_node_t;

typedef struct {
    sql_operator_t *left_child;
    int left_key_col;
    sql_operator_t *right_child;
    int right_key_col;
    hash_node_t *buckets[HASH_BUCKETS];
    sql_tuple_t curr_right;
    bool has_curr_right;
    hash_node_t *curr_node;
} join_state_t;

static void join_open(sql_operator_t *op) {
    join_state_t *st = (join_state_t *)op->state;
    for (int i = 0; i < HASH_BUCKETS; i++) st->buckets[i] = NULL;

    st->left_child->open(st->left_child);
    sql_tuple_t lt;
    while (st->left_child->next(st->left_child, &lt)) {
        uint64_t k = (uint64_t)lt.cols[st->left_key_col];
        size_t b = k % HASH_BUCKETS;
        hash_node_t *n = (hash_node_t *)malloc(sizeof(hash_node_t));
        n->tuple = lt;
        n->next = st->buckets[b];
        st->buckets[b] = n;
    }

    st->right_child->open(st->right_child);
    st->has_curr_right = false;
    st->curr_node = NULL;
}

static bool join_next(sql_operator_t *op, sql_tuple_t *out_tuple) {
    join_state_t *st = (join_state_t *)op->state;
    while (true) {
        if (st->curr_node) {
            hash_node_t *n = st->curr_node;
            st->curr_node = n->next;
            if (n->tuple.cols[st->left_key_col] == st->curr_right.cols[st->right_key_col]) {
                out_tuple->cols[0] = n->tuple.cols[0];
                out_tuple->cols[1] = n->tuple.cols[1];
                out_tuple->cols[2] = st->curr_right.cols[0];
                out_tuple->cols[3] = st->curr_right.cols[1];
                return true;
            }
            continue;
        }

        if (!st->right_child->next(st->right_child, &st->curr_right)) {
            return false;
        }
        st->has_curr_right = true;
        uint64_t k = (uint64_t)st->curr_right.cols[st->right_key_col];
        size_t b = k % HASH_BUCKETS;
        st->curr_node = st->buckets[b];
    }
}

static void join_close(sql_operator_t *op) {
    join_state_t *st = (join_state_t *)op->state;
    for (int i = 0; i < HASH_BUCKETS; i++) {
        hash_node_t *n = st->buckets[i];
        while (n) {
            hash_node_t *tmp = n->next;
            free(n);
            n = tmp;
        }
    }
    st->left_child->close(st->left_child);
    free(st->left_child);
    st->right_child->close(st->right_child);
    free(st->right_child);
    free(op->state);
}

sql_operator_t* sql_make_hash_join_op(sql_operator_t *left_child, int left_key_col,
                                      sql_operator_t *right_child, int right_key_col) {
    sql_operator_t *op = (sql_operator_t *)malloc(sizeof(sql_operator_t));
    join_state_t *st = (join_state_t *)malloc(sizeof(join_state_t));
    st->left_child = left_child;
    st->left_key_col = left_key_col;
    st->right_child = right_child;
    st->right_key_col = right_key_col;
    op->open = join_open;
    op->next = join_next;
    op->close = join_close;
    op->state = st;
    return op;
}

/* 4. Group-By Hash Aggregation Operator */
typedef struct agg_group {
    int64_t group_key;
    int64_t count;
    int64_t sum;
    int64_t max_val;
    struct agg_group *next;
} agg_group_t;

typedef struct {
    sql_operator_t *child;
    int group_col;
    int val_col;
    sql_tuple_t *sorted_groups;
    size_t num_groups;
    size_t curr_idx;
} agg_state_t;

static int compare_tuples_group(const void *a, const void *b) {
    const sql_tuple_t *ta = (const sql_tuple_t *)a;
    const sql_tuple_t *tb = (const sql_tuple_t *)b;
    if (ta->cols[0] < tb->cols[0]) return -1;
    if (ta->cols[0] > tb->cols[0]) return 1;
    return 0;
}

static void agg_open(sql_operator_t *op) {
    agg_state_t *st = (agg_state_t *)op->state;
    agg_group_t *buckets[HASH_BUCKETS];
    for (int i = 0; i < HASH_BUCKETS; i++) buckets[i] = NULL;

    st->child->open(st->child);
    sql_tuple_t t;
    size_t total_unique = 0;

    while (st->child->next(st->child, &t)) {
        int64_t g = t.cols[st->group_col];
        int64_t v = t.cols[st->val_col];
        size_t b = ((uint64_t)g) % HASH_BUCKETS;

        agg_group_t *node = buckets[b];
        while (node) {
            if (node->group_key == g) break;
            node = node->next;
        }

        if (node) {
            node->count++;
            node->sum += v;
            if (v > node->max_val) node->max_val = v;
        } else {
            node = (agg_group_t *)malloc(sizeof(agg_group_t));
            node->group_key = g;
            node->count = 1;
            node->sum = v;
            node->max_val = v;
            node->next = buckets[b];
            buckets[b] = node;
            total_unique++;
        }
    }

    st->num_groups = total_unique;
    st->sorted_groups = (sql_tuple_t *)malloc(total_unique * sizeof(sql_tuple_t));
    size_t idx = 0;

    for (int i = 0; i < HASH_BUCKETS; i++) {
        agg_group_t *node = buckets[i];
        while (node) {
            agg_group_t *tmp = node->next;
            st->sorted_groups[idx].cols[0] = node->group_key;
            st->sorted_groups[idx].cols[1] = node->count;
            st->sorted_groups[idx].cols[2] = node->sum;
            st->sorted_groups[idx].cols[3] = node->max_val;
            idx++;
            free(node);
            node = tmp;
        }
    }

    qsort(st->sorted_groups, total_unique, sizeof(sql_tuple_t), compare_tuples_group);
    st->curr_idx = 0;
}

static bool agg_next(sql_operator_t *op, sql_tuple_t *out_tuple) {
    agg_state_t *st = (agg_state_t *)op->state;
    if (st->curr_idx < st->num_groups) {
        *out_tuple = st->sorted_groups[st->curr_idx++];
        return true;
    }
    return false;
}

static void agg_close(sql_operator_t *op) {
    agg_state_t *st = (agg_state_t *)op->state;
    free(st->sorted_groups);
    st->child->close(st->child);
    free(st->child);
    free(op->state);
}

sql_operator_t* sql_make_hash_agg_op(sql_operator_t *child, int group_col, int val_col) {
    sql_operator_t *op = (sql_operator_t *)malloc(sizeof(sql_operator_t));
    agg_state_t *st = (agg_state_t *)malloc(sizeof(agg_state_t));
    st->child = child;
    st->group_col = group_col;
    st->val_col = val_col;
    st->sorted_groups = NULL;
    st->num_groups = 0;
    st->curr_idx = 0;
    op->open = agg_open;
    op->next = agg_next;
    op->close = agg_close;
    op->state = st;
    return op;
}

int main() {
    printf("Starting Relational Volcano Query Execution Engine Verification under ASAN...\n");

    sql_tuple_t customers[100];
    for (int i = 0; i < 100; i++) {
        customers[i].cols[0] = i + 1;
        customers[i].cols[1] = (i % 5) + 10;
        customers[i].cols[2] = (i % 3) + 1;
        customers[i].cols[3] = 0;
    }

    sql_tuple_t orders[500];
    for (int i = 0; i < 500; i++) {
        orders[i].cols[0] = 1000 + i;
        orders[i].cols[1] = (i % 100) + 1;
        orders[i].cols[2] = ((i * 37) % 200) + 10;
        orders[i].cols[3] = 0;
    }

    sql_operator_t *scan_cust = sql_make_scan_op(customers, 100);
    if (!scan_cust) return 1;
    sql_operator_t *filter_cust = sql_make_filter_op(scan_cust, 2, 2);
    if (!filter_cust) return 1;

    sql_operator_t *scan_orders = sql_make_scan_op(orders, 500);
    if (!scan_orders) return 1;

    sql_operator_t *join_op = sql_make_hash_join_op(filter_cust, 0, scan_orders, 1);
    if (!join_op) return 1;

    sql_operator_t *agg_op = sql_make_hash_agg_op(join_op, 1, 3);
    if (!agg_op) return 1;

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
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -fsanitize=address,undefined -o "$OUT_DIR/sql_bench" "$TARGET_PATH"
"$OUT_DIR/sql_bench" > /tmp/out.log
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
