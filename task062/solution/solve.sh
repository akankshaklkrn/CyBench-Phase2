#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import struct
import json
import os
from collections import defaultdict

class PacketForensics:
    def analyze(self, filepath: str) -> dict:
        session_packets = defaultdict(list)
        
        with open(filepath, 'r') as f:
            for line in f:
                line = line.strip()
                if not line or '|' not in line:
                    continue
                sess_id, hex_frame = line.split('|', 1)
                frame = bytes.fromhex(hex_frame)
                session_packets[sess_id].append(frame)
                
        results = {}
        for sess_id, frames in session_packets.items():
            # Parse packets in this session
            syn_count = 0
            ack_count = 0
            syn_ack_count = 0
            dst_ports = set()
            max_dns_label_len = 0
            is_udp = False
            has_slowloris_pattern = False
            has_benign_http = False
            
            for frame in frames:
                if len(frame) < 14:
                    continue
                # Eth header
                ethertype = struct.unpack("!H", frame[12:14])[0]
                if ethertype != 0x0800:
                    continue
                    
                ip_hdr_raw = frame[14:]
                if len(ip_hdr_raw) < 20:
                    continue
                    
                ihl = (ip_hdr_raw[0] & 0x0F) * 4
                proto = ip_hdr_raw[9]
                payload_raw = ip_hdr_raw[ihl:]
                
                if proto == 17: # UDP
                    is_udp = True
                    if len(payload_raw) >= 8:
                        src_p, dst_p, udp_len = struct.unpack("!HHH", payload_raw[:6])
                        dns_payload = payload_raw[8:]
                        if dst_p == 53 and len(dns_payload) > 12:
                            # Parse DNS QNAME
                            q_idx = 12
                            labels = []
                            while q_idx < len(dns_payload):
                                l_len = dns_payload[q_idx]
                                if l_len == 0:
                                    break
                                label = dns_payload[q_idx+1 : q_idx+1+l_len]
                                labels.append(label)
                                q_idx += 1 + l_len
                            if labels:
                                max_dns_label_len = max(max_dns_label_len, max(len(l) for l in labels))
                                
                elif proto == 6: # TCP
                    if len(payload_raw) >= 20:
                        src_p, dst_p, seq, ack, offset_res, flags = struct.unpack("!HHIIBB", payload_raw[:14])
                        tcp_hdr_len = ((offset_res >> 4) & 0x0F) * 4
                        tcp_payload = payload_raw[tcp_hdr_len:]
                        
                        dst_ports.add(dst_p)
                        
                        is_syn = bool(flags & 0x02)
                        is_ack = bool(flags & 0x10)
                        
                        if is_syn and is_ack:
                            syn_ack_count += 1
                        elif is_syn:
                            syn_count += 1
                        elif is_ack:
                            ack_count += 1
                            
                        if b"Slowloris" in tcp_payload or (b"X-Header-" in tcp_payload and b"\r\n\r\n" not in tcp_payload):
                            has_slowloris_pattern = True
                        if b"HTTP/1.1 200 OK" in tcp_payload:
                            has_benign_http = True
                            
            # Classification rules
            if is_udp and max_dns_label_len > 30:
                results[sess_id] = "DNS_TUNNEL"
            elif len(dst_ports) >= 5:
                results[sess_id] = "PORT_SCAN"
            elif syn_count >= 5 and syn_ack_count == 0 and ack_count == 0:
                results[sess_id] = "SYN_FLOOD"
            elif has_slowloris_pattern:
                results[sess_id] = "SLOWLORIS"
            elif has_benign_http or (syn_ack_count > 0 and ack_count > 0):
                results[sess_id] = "BENIGN"
            else:
                results[sess_id] = "BENIGN"
                
        return results

if __name__ == "__main__":
    pp = "/tests/packets.hex"
    if not os.path.exists(pp):
        pp = "/Users/jatinjena/Downloads/tasknew/task069/tests/packets.hex"
    pf = PacketForensics()
    res = pf.analyze(pp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/classifications.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
