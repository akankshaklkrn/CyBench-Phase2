# Task 086: Network Security — eBPF XDP Packet Inspector & Firewall State Machine

You are a kernel network security engineer building an **eBPF XDP (eXpress Data Path) Packet Inspection State Machine**.

## XDP Packet Processing Logic

Given a stream of network packet header metadata (`tests/xdp_packets.json`):

1. **Ethernet & IP Protocol Parsing**:
   - `eth_proto`: Must be IPv4 (`0x0800`). Non-IPv4 packets return `XDP_PASS`.
   - `ip_proto`: TCP (`6`) or UDP (`17`).
2. **SYN-Flood & Rate Limit Detection**:
   - For TCP SYN packets (`tcp_flags & 0x02` and not `ACK`), track connection attempt rate per `src_ip`.
   - If a single `src_ip` exceeds `max_syn_per_sec` threshold (e.g. $> 5$ SYN packets within window), mark IP as **blocked** and return `XDP_DROP` for all subsequent packets from that `src_ip`.
3. **Blocked Port Rules**:
   - If destination port is in `blocked_ports` list (e.g. `23` Telnet), return `XDP_DROP`.
4. **Action Values**:
   - Return string: `"XDP_PASS"` or `"XDP_DROP"`.

## Input Schema (`tests/xdp_packets.json`)

```json
{
  "max_syn_per_sec": 5,
  "blocked_ports": [23, 135, 445],
  "packets": [
    {
      "packet_id": 1,
      "eth_proto": "0x0800",
      "src_ip": "192.168.1.100",
      "dst_port": 80,
      "ip_proto": 6,
      "tcp_flags": 2
    }
  ]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `XDPPacketInspector`:
```python
class XDPPacketInspector:
    def inspect_traffic(self, filepath: str) -> dict:
        # filepath: path to xdp_packets.json
        # returns: dict {"decisions": [{"packet_id": 1, "action": "XDP_PASS"}, ...], "blocked_ips": ["192.168.1.100"]}
        pass
```

When run directly (`python3 solution.py`), write output to `/src/xdp_result.json`.

## Constraints
- **Python Standard Library Only** (`json`, `os`, `sys`).
- Dynamic relative path resolution MUST be used for output.
