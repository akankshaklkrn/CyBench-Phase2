#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import os
from collections import defaultdict

class XDPPacketInspector:
    def inspect_traffic(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        max_syn = data.get('max_syn_per_sec', 5)
        blocked_ports = set(data.get('blocked_ports', []))
        packets = data.get('packets', [])
        
        syn_counts = defaultdict(int)
        blocked_ips = set()
        decisions = []
        
        for pkt in packets:
            pid = pkt['packet_id']
            src = pkt['src_ip']
            dst_port = pkt['dst_port']
            eth_proto = pkt.get('eth_proto', '')
            flags = pkt.get('tcp_flags', 0)
            
            # Non-IPv4 -> XDP_PASS
            if eth_proto != '0x0800':
                decisions.append({"packet_id": pid, "action": "XDP_PASS"})
                continue
                
            # Already blocked IP -> XDP_DROP
            if src in blocked_ips:
                decisions.append({"packet_id": pid, "action": "XDP_DROP"})
                continue
                
            # Blocked port -> XDP_DROP
            if dst_port in blocked_ports:
                decisions.append({"packet_id": pid, "action": "XDP_DROP"})
                continue
                
            # SYN flag (0x02) check
            if (flags & 0x02) != 0 and (flags & 0x10) == 0:
                syn_counts[src] += 1
                if syn_counts[src] > max_syn:
                    blocked_ips.add(src)
                    decisions.append({"packet_id": pid, "action": "XDP_DROP"})
                    continue
                    
            decisions.append({"packet_id": pid, "action": "XDP_PASS"})
            
        return {
            "decisions": decisions,
            "blocked_ips": sorted(list(blocked_ips))
        }

if __name__ == "__main__":
    fp = "/tests/xdp_packets.json"
    if not os.path.exists(fp):
        fp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tests", "xdp_packets.json")
    inspector = XDPPacketInspector()
    res = inspector.inspect_traffic(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/xdp_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
