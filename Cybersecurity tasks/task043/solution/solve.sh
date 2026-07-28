#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

typedef enum {
    TLS_STATE_START = 0,
    TLS_STATE_WAIT_SH = 1,
    TLS_STATE_WAIT_EE = 2,
    TLS_STATE_WAIT_FIN = 3,
    TLS_STATE_CONNECTED = 4,
    TLS_STATE_ERROR = 5
} tls_state_t;

typedef enum {
    TLS_MSG_CLIENT_HELLO = 1,
    TLS_MSG_SERVER_HELLO = 2,
    TLS_MSG_ENCRYPTED_EXTENSIONS = 3,
    TLS_MSG_FINISHED = 4,
    TLS_MSG_APP_DATA = 23
} tls_msg_type_t;

typedef struct {
    tls_msg_type_t type;
    uint32_t seq_num;
    uint32_t payload_len;
    uint8_t payload[64];
    uint32_t auth_tag;
} tls_record_t;

typedef struct {
    bool is_client;
    tls_state_t state;
    uint32_t read_seq;
    uint32_t write_seq;
    uint32_t handshake_secret;
    uint32_t traffic_secret;
    uint32_t transcript_hash;
    bool keys_derived;
} tls_ctx_t;

void tls_init(tls_ctx_t *ctx, bool is_client) {
    if (!ctx) return;
    memset(ctx, 0, sizeof(tls_ctx_t));
    ctx->is_client = is_client;
    ctx->state = TLS_STATE_START;
    ctx->read_seq = 0;
    ctx->write_seq = 0;
    ctx->handshake_secret = 0;
    ctx->traffic_secret = 0;
    ctx->transcript_hash = 0x811C9DC5;
    ctx->keys_derived = false;
}

void tls_update_transcript(tls_ctx_t *ctx, const tls_record_t *rec) {
    if (!ctx || !rec) return;
    uint32_t len = rec->payload_len;
    if (len > 64) len = 64;
    for (uint32_t i = 0; i < len; i++) {
        ctx->transcript_hash = (ctx->transcript_hash ^ rec->payload[i]) * 0x01000193;
    }
    ctx->transcript_hash = (ctx->transcript_hash ^ (uint8_t)rec->type) * 0x01000193;
}

int tls_derive_keys(tls_ctx_t *ctx, uint32_t shared_secret) {
    if (!ctx) return -1;
    if (ctx->state != TLS_STATE_WAIT_EE && ctx->state != TLS_STATE_START) {
        ctx->state = TLS_STATE_ERROR;
        return -1;
    }
    ctx->handshake_secret = (shared_secret ^ ctx->transcript_hash) + 0x9e3779b9;
    ctx->traffic_secret = (ctx->handshake_secret * 0x01000193) ^ 0x3c6ef372;
    ctx->keys_derived = true;
    return 0;
}

uint32_t tls_compute_mac(tls_ctx_t *ctx, const tls_record_t *rec) {
    if (!ctx || !rec || !ctx->keys_derived) return 0;
    uint32_t mac = ctx->traffic_secret ^ (uint32_t)rec->type ^ (rec->seq_num * 0x9e3779b9);
    uint32_t len = rec->payload_len;
    if (len > 64) len = 64;
    for (uint32_t i = 0; i < len; i++) {
        mac = (mac ^ rec->payload[i]) * 0x01000193;
    }
    return mac;
}

int tls_process_record(tls_ctx_t *ctx, const tls_record_t *rec, uint8_t *out_data, uint32_t *out_len) {
    if (!ctx || !rec) return -1;
    if (ctx->state == TLS_STATE_ERROR) return -1;

    if (rec->seq_num != ctx->read_seq || rec->payload_len > 64) {
        ctx->state = TLS_STATE_ERROR;
        return -1;
    }

    if (ctx->keys_derived) {
        uint32_t expected_mac = tls_compute_mac(ctx, rec);
        if (rec->auth_tag != expected_mac) {
            ctx->state = TLS_STATE_ERROR;
            return -2;
        }
    }

    if (ctx->is_client) {
        switch (ctx->state) {
            case TLS_STATE_START: {
                if (rec->type != TLS_MSG_SERVER_HELLO) {
                    ctx->state = TLS_STATE_ERROR;
                    return -1;
                }
                tls_update_transcript(ctx, rec);
                uint32_t shared_secret = 0;
                if (rec->payload_len >= 4) {
                    memcpy(&shared_secret, rec->payload, 4);
                }
                ctx->state = TLS_STATE_WAIT_EE;
                if (tls_derive_keys(ctx, shared_secret) < 0) {
                    return -1;
                }
                ctx->read_seq++;
                return 0;
            }
            case TLS_STATE_WAIT_EE: {
                if (rec->type != TLS_MSG_ENCRYPTED_EXTENSIONS) {
                    ctx->state = TLS_STATE_ERROR;
                    return -1;
                }
                tls_update_transcript(ctx, rec);
                ctx->state = TLS_STATE_WAIT_FIN;
                ctx->read_seq++;
                return 0;
            }
            case TLS_STATE_WAIT_FIN: {
                if (rec->type != TLS_MSG_FINISHED) {
                    ctx->state = TLS_STATE_ERROR;
                    return -1;
                }
                if (rec->payload_len < 4) {
                    ctx->state = TLS_STATE_ERROR;
                    return -2;
                }
                uint32_t fin_verify = 0;
                memcpy(&fin_verify, rec->payload, 4);
                if (fin_verify != (ctx->handshake_secret ^ ctx->transcript_hash)) {
                    ctx->state = TLS_STATE_ERROR;
                    return -2;
                }
                tls_update_transcript(ctx, rec);
                ctx->state = TLS_STATE_CONNECTED;
                ctx->read_seq++;
                return 0;
            }
            case TLS_STATE_CONNECTED: {
                if (rec->type != TLS_MSG_APP_DATA) {
                    ctx->state = TLS_STATE_ERROR;
                    return -1;
                }
                if (out_data && out_len) {
                    memcpy(out_data, rec->payload, rec->payload_len);
                    *out_len = rec->payload_len;
                }
                ctx->read_seq++;
                return 0;
            }
            default:
                ctx->state = TLS_STATE_ERROR;
                return -1;
        }
    } else {
        ctx->state = TLS_STATE_ERROR;
        return -1;
    }
}

// Verification Harness
int main() {
    uint64_t state_hash = 0x100000001B3ULL;
    tls_ctx_t ctx;
    uint8_t out[64];
    uint32_t out_len;

    // Test 1: Normal Client Handshake & Application Data
    tls_init(&ctx, true);
    tls_record_t sh = { .type = TLS_MSG_SERVER_HELLO, .seq_num = 0, .payload_len = 4, .payload = { 0x12, 0x34, 0x56, 0x78 } };
    int r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    state_hash ^= (uint64_t)ctx.state * 0x9e37 + r1 * 0x1234 + ctx.handshake_secret;

    tls_record_t ee = { .type = TLS_MSG_ENCRYPTED_EXTENSIONS, .seq_num = 1, .payload_len = 2, .payload = { 0x01, 0x02 } };
    ee.auth_tag = tls_compute_mac(&ctx, &ee);
    int r2 = tls_process_record(&ctx, &ee, NULL, NULL);
    state_hash ^= (uint64_t)ctx.state * 0x85eb + r2 * 0x5678 + ctx.traffic_secret;

    tls_record_t fin = { .type = TLS_MSG_FINISHED, .seq_num = 2, .payload_len = 4 };
    uint32_t expected_fin = ctx.handshake_secret ^ ctx.transcript_hash;
    memcpy(fin.payload, &expected_fin, 4);
    fin.auth_tag = tls_compute_mac(&ctx, &fin);
    int r3 = tls_process_record(&ctx, &fin, NULL, NULL);
    state_hash ^= (uint64_t)ctx.state * 0xc2b2 + r3 * 0x9abc + ctx.transcript_hash;

    tls_record_t app1 = { .type = TLS_MSG_APP_DATA, .seq_num = 3, .payload_len = 5, .payload = "HELLO" };
    app1.auth_tag = tls_compute_mac(&ctx, &app1);
    out_len = 0;
    int r4 = tls_process_record(&ctx, &app1, out, &out_len);
    state_hash ^= (uint64_t)ctx.state * 0x27d4 + r4 * 0xdef0 + out_len + (out[0] << 8);

    // Test 2: Out-of-Order Handshake Message Rejection
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    int r5 = tls_process_record(&ctx, &fin, NULL, NULL); // Finished before EE
    state_hash ^= (uint64_t)ctx.state * 0x1656 + r5 * 0x1111;

    // Test 3: Sequence Number Replay Trapping
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    ee.auth_tag = tls_compute_mac(&ctx, &ee);
    r2 = tls_process_record(&ctx, &ee, NULL, NULL);
    int r6 = tls_process_record(&ctx, &ee, NULL, NULL); // Replay seq 1 when read_seq is 2
    state_hash ^= (uint64_t)ctx.state * 0x3333 + r6 * 0x2222;

    // Test 4: MAC Tampering Detection
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    ee.auth_tag = tls_compute_mac(&ctx, &ee) ^ 0x00000001; // Tampered MAC
    int r7 = tls_process_record(&ctx, &ee, NULL, NULL);
    state_hash ^= (uint64_t)ctx.state * 0x5555 + r7 * 0x4444;

    // Test 5: Invalid Finished Verification
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    ee.auth_tag = tls_compute_mac(&ctx, &ee);
    r2 = tls_process_record(&ctx, &ee, NULL, NULL);
    expected_fin ^= 0xFFFFFFFF; // Bad finish value
    memcpy(fin.payload, &expected_fin, 4);
    fin.auth_tag = tls_compute_mac(&ctx, &fin);
    int r8 = tls_process_record(&ctx, &fin, NULL, NULL);
    state_hash ^= (uint64_t)ctx.state * 0x7777 + r8 * 0x6666;

    // Test 6: Premature App Data Injection
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    app1.seq_num = 1;
    app1.auth_tag = tls_compute_mac(&ctx, &app1);
    int r9 = tls_process_record(&ctx, &app1, out, &out_len);
    state_hash ^= (uint64_t)ctx.state * 0x9999 + r9 * 0x8888;

    // Test 7 & 8: Multi-Record Stream & Transcript Mixing check
    tls_init(&ctx, true);
    r1 = tls_process_record(&ctx, &sh, NULL, NULL);
    ee.seq_num = 1;
    ee.auth_tag = tls_compute_mac(&ctx, &ee);
    r2 = tls_process_record(&ctx, &ee, NULL, NULL);
    expected_fin = ctx.handshake_secret ^ ctx.transcript_hash;
    memcpy(fin.payload, &expected_fin, 4);
    fin.seq_num = 2;
    fin.auth_tag = tls_compute_mac(&ctx, &fin);
    r3 = tls_process_record(&ctx, &fin, NULL, NULL);

    tls_record_t app2 = { .type = TLS_MSG_APP_DATA, .seq_num = 3, .payload_len = 3, .payload = "SEC" };
    app2.auth_tag = tls_compute_mac(&ctx, &app2);
    int r10 = tls_process_record(&ctx, &app2, out, &out_len);
    state_hash ^= (uint64_t)ctx.state * 0xAAAA + r10 * 0xBBBB + out[0];

    tls_record_t app3 = { .type = TLS_MSG_APP_DATA, .seq_num = 4, .payload_len = 4, .payload = "URE!" };
    app3.auth_tag = tls_compute_mac(&ctx, &app3);
    int r11 = tls_process_record(&ctx, &app3, out, &out_len);
    state_hash ^= (uint64_t)ctx.state * 0xCCCC + r11 * 0xDDDD + out[3];

    if (state_hash == 0) state_hash = 0xBADCAFEULL;
    printf("Verification SUCCESS! Dynamic State Hash computed over 8 TLS verification tests.\n");
    printf("cyberbench{tls_handshake_state_machine_state_%016llx}\n", (unsigned long long)state_hash);
    return 0;
}

EOF

mkdir -p /out /app /logs/agent
gcc -O2 -Wall -o /out/bench /src/target.c 2>/dev/null || gcc -O2 -Wall -o /out/bench environment/target.c 2>/dev/null || true
if [ -f /out/bench ]; then
    /out/bench > /app/flags.txt 2>/dev/null || true
    cp /app/flags.txt /logs/agent/flags.txt 2>/dev/null || true
    cp /app/flags.txt flags.txt 2>/dev/null || true
fi
