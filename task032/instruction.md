# Challenge: Zero-Copy Network Ring Buffer Packet Pipeline (`user_net_stack_l0`)

You are tasked with building a high-performance, zero-copy user-space network packet processing pipeline in C (inspired by DPDK / eBPF XDP). The system receives raw Ethernet frames via a circular ring buffer, validates network layer headers, recalculates RFC-compliant checksums, routes valid packets, and aggregates flow statistics.

## Technical Specifications & Architecture

### 1. Circular Ring Buffer (`net_ring_t`)
The network driver enqueues raw packet descriptors into a circular ring buffer. You must implement lock-free single-producer/single-consumer wrap-around arithmetic:
- Capacity: `RING_CAPACITY = 1024` slots (power of 2).
- When enqueueing, if `(tail + 1) % RING_CAPACITY == head`, the ring is full; return `false`.
- When dequeueing, if `head == tail`, the ring is empty; return `false`.
- Every packet slot holds a pointer to a packet buffer and its length.

### 2. Protocol Header Layouts (Packed Structs)
You must handle strict byte alignment and network byte ordering (`ntohs` / `htons` / `ntohl` / `htonl`):
- **Ethernet Header (`eth_hdr_t`)**: 6 bytes Destination MAC, 6 bytes Source MAC, 2 bytes EtherType (must match `0x0800` for IPv4).
- **IPv4 Header (`ipv4_hdr_t`)**: 1 byte Version/IHL (must be `0x45` for IPv4 with 20-byte header), 1 byte TOS, 2 bytes Total Length, 2 bytes Identification, 2 bytes Flags/Fragment Offset, 1 byte TTL, 1 byte Protocol (must be `17` for UDP), 2 bytes Header Checksum, 4 bytes Source IP, 4 bytes Destination IP.
- **UDP Header (`udp_hdr_t`)**: 2 bytes Source Port, 2 bytes Destination Port, 2 bytes Length, 2 bytes Checksum.

### 3. RFC-Compliant Internet Checksum Calculation
You must implement `uint16_t calc_ipv4_checksum(ipv4_hdr_t *ip)`:
- Compute the standard 16-bit one's complement sum of all 10 16-bit words in the IPv4 header (with the existing Checksum field set to 0 during calculation).
- Fold any carry bits beyond 16 bits back into the lower 16 bits: `while (sum >> 16) sum = (sum & 0xffff) + (sum >> 16);`.
- Take the one's complement (`~sum`) as the final check value.
- When validating an incoming packet, if its stored checksum does not equal the calculated checksum, drop the packet and increment `stats.dropped_bad_checksum`.

### 4. Packet Routing & TTL Decrement
For every valid IPv4/UDP packet dequeued from the ring buffer:
- Verify EtherType == `0x0800`, IPv4 Version/IHL == `0x45`, Protocol == `17` (UDP), and valid IPv4 checksum.
- Check TTL: If `ttl <= 1`, drop the packet and increment `stats.dropped_ttl_expired`.
- Decrement TTL by 1 (`ip->ttl--`).
- Recalculate and update the IPv4 header checksum (`ip->checksum = calc_ipv4_checksum(ip)`).
- Extract the 5-tuple flow identifier `(src_ip, dst_ip, src_port, dst_port, proto)` and aggregate payload bytes into the flow statistics routing table.

### 5. Sanitization & Dynamic Flag Emission
- The binary is compiled under **AddressSanitizer (`-fsanitize=address,undefined`)**.
- There are NO hardcoded flag strings anywhere in the binary or filesystem.
- After processing 10,000 synthetic network frames, the test harness computes an order-independent commutative XOR sum over all surviving flow routing metrics and packet drop counters to dynamically output `cyberbench{net_stack_ring_<hash>}`.
- Any memory corruption, out-of-bounds ring buffer indexing, or incorrect RFC checksum calculation will result in verification failure.

## Functions to Implement in `target.c`
```c
bool ring_init(net_ring_t *ring);
void ring_destroy(net_ring_t *ring);
bool ring_enqueue(net_ring_t *ring, uint8_t *pkt_data, uint16_t len);
bool ring_dequeue(net_ring_t *ring, uint8_t **pkt_data_out, uint16_t *len_out);
uint16_t calc_ipv4_checksum(ipv4_hdr_t *ip);
bool process_packet(net_pipeline_t *pipeline, uint8_t *pkt_data, uint16_t len);
void run_pipeline_batch(net_pipeline_t *pipeline, int batch_size);
```
