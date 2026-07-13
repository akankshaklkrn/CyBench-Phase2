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
#include <arpa/inet.h>

#define RING_CAPACITY 1024
#define MAX_FLOWS 256
#define NUM_PACKETS 10000

typedef struct {
    uint8_t *data;
    uint16_t len;
} ring_slot_t;

typedef struct {
    ring_slot_t slots[RING_CAPACITY];
    volatile uint32_t head;
    volatile uint32_t tail;
} net_ring_t;

typedef struct __attribute__((packed)) {
    uint8_t dst_mac[6];
    uint8_t src_mac[6];
    uint16_t eth_type;
} eth_hdr_t;

typedef struct __attribute__((packed)) {
    uint8_t ver_ihl;
    uint8_t tos;
    uint16_t total_len;
    uint16_t id;
    uint16_t flags_fo;
    uint8_t ttl;
    uint8_t proto;
    uint16_t checksum;
    uint32_t src_ip;
    uint32_t dst_ip;
} ipv4_hdr_t;

typedef struct __attribute__((packed)) {
    uint16_t src_port;
    uint16_t dst_port;
    uint16_t len;
    uint16_t checksum;
} udp_hdr_t;

typedef struct {
    uint32_t src_ip;
    uint32_t dst_ip;
    uint16_t src_port;
    uint16_t dst_port;
    uint8_t proto;
    uint64_t total_bytes;
    uint64_t packet_count;
    bool is_active;
} flow_entry_t;

typedef struct {
    flow_entry_t flows[MAX_FLOWS];
    uint64_t dropped_bad_eth;
    uint64_t dropped_bad_ipv4;
    uint64_t dropped_bad_checksum;
    uint64_t dropped_ttl_expired;
    uint64_t forwarded_packets;
} net_stats_t;

typedef struct {
    net_ring_t rx_ring;
    net_stats_t stats;
} net_pipeline_t;

static inline uint64_t flow_hash(uint32_t sip, uint32_t dip, uint16_t sport, uint16_t dport, uint8_t proto) {
    uint64_t h = sip ^ ((uint64_t)dip << 32);
    h ^= (sport << 16) | dport | ((uint64_t)proto << 48);
    h ^= h >> 33;
    h *= 0xff51afd7ed558ccdULL;
    h ^= h >> 33;
    h *= 0xc4ceb9fe1a85ec53ULL;
    h ^= h >> 33;
    return h;
}

bool ring_init(net_ring_t *ring) {
    memset(ring->slots, 0, sizeof(ring->slots));
    ring->head = 0;
    ring->tail = 0;
    return true;
}

void ring_destroy(net_ring_t *ring) {
    while (ring->head != ring->tail) {
        if (ring->slots[ring->head].data) {
            free(ring->slots[ring->head].data);
            ring->slots[ring->head].data = NULL;
        }
        ring->head = (ring->head + 1) % RING_CAPACITY;
    }
}

bool ring_enqueue(net_ring_t *ring, uint8_t *pkt_data, uint16_t len) {
    uint32_t next_tail = (ring->tail + 1) % RING_CAPACITY;
    if (next_tail == ring->head) {
        return false;
    }
    uint8_t *copy = (uint8_t *)malloc(len);
    if (!copy) return false;
    memcpy(copy, pkt_data, len);
    ring->slots[ring->tail].data = copy;
    ring->slots[ring->tail].len = len;
    ring->tail = next_tail;
    return true;
}

bool ring_dequeue(net_ring_t *ring, uint8_t **pkt_data_out, uint16_t *len_out) {
    if (ring->head == ring->tail) {
        return false;
    }
    *pkt_data_out = ring->slots[ring->head].data;
    *len_out = ring->slots[ring->head].len;
    ring->slots[ring->head].data = NULL;
    ring->head = (ring->head + 1) % RING_CAPACITY;
    return true;
}

uint16_t calc_ipv4_checksum(ipv4_hdr_t *ip) {
    uint16_t old_csum = ip->checksum;
    ip->checksum = 0;
    uint32_t sum = 0;
    uint8_t *ptr = (uint8_t *)ip;
    for (int i = 0; i < 20; i += 2) {
        sum += (ptr[i] << 8) | ptr[i + 1];
    }
    while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
    ip->checksum = old_csum;
    return htons(~sum);
}

bool process_packet(net_pipeline_t *pipeline, uint8_t *pkt_data, uint16_t len) {
    if (len < sizeof(eth_hdr_t) + sizeof(ipv4_hdr_t) + sizeof(udp_hdr_t)) {
        pipeline->stats.dropped_bad_eth++;
        return false;
    }
    eth_hdr_t *eth = (eth_hdr_t *)pkt_data;
    if (ntohs(eth->eth_type) != 0x0800) {
        pipeline->stats.dropped_bad_eth++;
        return false;
    }
    ipv4_hdr_t *ip = (ipv4_hdr_t *)(pkt_data + sizeof(eth_hdr_t));
    if (ip->ver_ihl != 0x45 || ip->proto != 17) {
        pipeline->stats.dropped_bad_ipv4++;
        return false;
    }
    uint16_t calc_csum = calc_ipv4_checksum(ip);
    if (ip->checksum != calc_csum) {
        pipeline->stats.dropped_bad_checksum++;
        return false;
    }
    if (ip->ttl <= 1) {
        pipeline->stats.dropped_ttl_expired++;
        return false;
    }
    ip->ttl--;
    ip->checksum = calc_ipv4_checksum(ip);
    
    udp_hdr_t *udp = (udp_hdr_t *)(pkt_data + sizeof(eth_hdr_t) + sizeof(ipv4_hdr_t));
    uint32_t sip = ntohl(ip->src_ip);
    uint32_t dip = ntohl(ip->dst_ip);
    uint16_t sport = ntohs(udp->src_port);
    uint16_t dport = ntohs(udp->dst_port);
    uint8_t proto = ip->proto;
    
    int empty_idx = -1;
    for (int i = 0; i < MAX_FLOWS; i++) {
        if (pipeline->stats.flows[i].is_active) {
            if (pipeline->stats.flows[i].src_ip == sip &&
                pipeline->stats.flows[i].dst_ip == dip &&
                pipeline->stats.flows[i].src_port == sport &&
                pipeline->stats.flows[i].dst_port == dport &&
                pipeline->stats.flows[i].proto == proto) {
                pipeline->stats.flows[i].total_bytes += len;
                pipeline->stats.flows[i].packet_count++;
                pipeline->stats.forwarded_packets++;
                return true;
            }
        } else if (empty_idx == -1) {
            empty_idx = i;
        }
    }
    if (empty_idx != -1) {
        pipeline->stats.flows[empty_idx].src_ip = sip;
        pipeline->stats.flows[empty_idx].dst_ip = dip;
        pipeline->stats.flows[empty_idx].src_port = sport;
        pipeline->stats.flows[empty_idx].dst_port = dport;
        pipeline->stats.flows[empty_idx].proto = proto;
        pipeline->stats.flows[empty_idx].total_bytes = len;
        pipeline->stats.flows[empty_idx].packet_count = 1;
        pipeline->stats.flows[empty_idx].is_active = true;
        pipeline->stats.forwarded_packets++;
        return true;
    }
    return false;
}

void run_pipeline_batch(net_pipeline_t *pipeline, int batch_size) {
    for (int i = 0; i < batch_size; i++) {
        uint8_t *pkt = NULL;
        uint16_t len = 0;
        if (!ring_dequeue(&pipeline->rx_ring, &pkt, &len)) {
            break;
        }
        process_packet(pipeline, pkt, len);
        free(pkt);
    }
}

static void generate_test_packet(uint8_t *buf, uint16_t *len_out, int idx) {
    memset(buf, 0, 64);
    eth_hdr_t *eth = (eth_hdr_t *)buf;
    ipv4_hdr_t *ip = (ipv4_hdr_t *)(buf + sizeof(eth_hdr_t));
    udp_hdr_t *udp = (udp_hdr_t *)(buf + sizeof(eth_hdr_t) + sizeof(ipv4_hdr_t));
    
    eth->dst_mac[0] = 0x00; eth->dst_mac[1] = 0x11; eth->dst_mac[2] = 0x22;
    eth->dst_mac[3] = 0x33; eth->dst_mac[4] = 0x44; eth->dst_mac[5] = 0x55;
    eth->src_mac[0] = 0xAA; eth->src_mac[1] = 0xBB; eth->src_mac[2] = 0xCC;
    eth->src_mac[3] = 0xDD; eth->src_mac[4] = 0xEE; eth->src_mac[5] = 0xFF;
    eth->eth_type = htons(0x0800);
    
    ip->ver_ihl = 0x45;
    ip->tos = 0;
    uint16_t total_ip_len = sizeof(ipv4_hdr_t) + sizeof(udp_hdr_t) + 16;
    ip->total_len = htons(total_ip_len);
    ip->id = htons(idx);
    ip->flags_fo = 0;
    ip->ttl = 64;
    ip->proto = 17;
    ip->src_ip = htonl(0x0A000001 + (idx % 10));
    ip->dst_ip = htonl(0x0A000064 + ((idx / 10) % 5));
    
    udp->src_port = htons(1000 + (idx % 10));
    udp->dst_port = htons(80 + ((idx / 10) % 5));
    udp->len = htons(sizeof(udp_hdr_t) + 16);
    udp->checksum = 0;
    
    if (idx % 15 == 0) {
        eth->eth_type = htons(0x86DD);
    } else if (idx % 17 == 0) {
        ip->ver_ihl = 0x40;
    } else if (idx % 19 == 0) {
        ip->ttl = 1;
    }
    
    uint32_t sum = 0;
    ip->checksum = 0;
    uint8_t *ptr = (uint8_t *)ip;
    for (int i = 0; i < 20; i += 2) {
        sum += (ptr[i] << 8) | ptr[i + 1];
    }
    while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);
    ip->checksum = htons(~sum);
    
    if (idx % 23 == 0) {
        ip->checksum = htons(ntohs(ip->checksum) ^ 0x1234);
    }
    
    *len_out = sizeof(eth_hdr_t) + total_ip_len;
}

int main() {
    printf("Starting Zero-Copy Network Ring Buffer Packet Pipeline Verification under ASAN...\n");
    
    net_pipeline_t pipeline;
    memset(&pipeline, 0, sizeof(pipeline));
    if (!ring_init(&pipeline.rx_ring)) {
        printf("FAIL: ring_init returned false.\n");
        return 1;
    }
    
    printf("Executing Phase 1: Basic Enqueue / Dequeue verification...\n");
    uint8_t dummy_pkt[64] = {0};
    if (!ring_enqueue(&pipeline.rx_ring, dummy_pkt, 64)) {
        printf("FAIL: Phase 1 basic ring_enqueue failed.\n");
        ring_destroy(&pipeline.rx_ring);
        return 1;
    }
    uint8_t *out_pkt = NULL;
    uint16_t out_len = 0;
    if (!ring_dequeue(&pipeline.rx_ring, &out_pkt, &out_len) || out_len != 64) {
        printf("FAIL: Phase 1 basic ring_dequeue failed.\n");
        ring_destroy(&pipeline.rx_ring);
        return 1;
    }
    free(out_pkt);
    
    printf("Executing Phase 2: High-throughput packet ingestion and switch routing...\n");
    for (int i = 0; i < NUM_PACKETS; i++) {
        uint8_t pkt[128];
        uint16_t len = 0;
        generate_test_packet(pkt, &len, i);
        if (!ring_enqueue(&pipeline.rx_ring, pkt, len)) {
            run_pipeline_batch(&pipeline, 512);
            if (!ring_enqueue(&pipeline.rx_ring, pkt, len)) {
                printf("FAIL: Ring buffer enqueue deadlock at packet %d.\n", i);
                ring_destroy(&pipeline.rx_ring);
                return 1;
            }
        }
        if (i % 256 == 0) {
            run_pipeline_batch(&pipeline, 256);
        }
    }
    run_pipeline_batch(&pipeline, RING_CAPACITY);
    
    if (pipeline.stats.forwarded_packets == 0) {
        printf("FAIL: No packets were successfully forwarded.\n");
        ring_destroy(&pipeline.rx_ring);
        return 1;
    }
    
    uint64_t state_hash = 0xcbf29ce484222325ULL;
    state_hash ^= pipeline.stats.forwarded_packets * 0x100000001b3ULL;
    state_hash ^= pipeline.stats.dropped_bad_eth * 0x9e3779b97f4a7c15ULL;
    state_hash ^= pipeline.stats.dropped_bad_ipv4 * 0xbf58476d1ce4e5b9ULL;
    state_hash ^= pipeline.stats.dropped_bad_checksum * 0x94d049bb133111ebULL;
    state_hash ^= pipeline.stats.dropped_ttl_expired * 0xd6e8feb86659fd93ULL;
    
    for (int i = 0; i < MAX_FLOWS; i++) {
        if (pipeline.stats.flows[i].is_active) {
            uint64_t fh = flow_hash(pipeline.stats.flows[i].src_ip, pipeline.stats.flows[i].dst_ip,
                                    pipeline.stats.flows[i].src_port, pipeline.stats.flows[i].dst_port,
                                    pipeline.stats.flows[i].proto);
            fh ^= pipeline.stats.flows[i].total_bytes * 0x100000001b3ULL;
            fh ^= pipeline.stats.flows[i].packet_count * 0xc4ceb9fe1a85ec53ULL;
            state_hash ^= fh;
        }
    }
    
    printf("Verification SUCCESS! Dynamic State Hash computed.\n");
    printf("cyberbench{net_stack_ring_%016lx}\n", (unsigned long)state_hash);
    
    ring_destroy(&pipeline.rx_ring);
    return 0;
}
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -pthread -fsanitize=address,undefined -o "$OUT_DIR/net_bench" "$TARGET_PATH"
"$OUT_DIR/net_bench" > /tmp/out.log
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
