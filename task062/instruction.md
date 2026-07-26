# Task 069: Network Packet Forensics & Intrusion Detection

You are a Network Security Analyst investigating a series of network intrusions and suspicious traffic captures. You are given a file containing raw packet captures in hex format.

Your objective is to write a Python 3 script `solution.py` that parses the raw hex packet dumps, reconstructs the network flows/sessions, and correctly classifies each session into one of five threat categories.

## Input File Format

The file `tests/packets.hex` contains raw packet records, one per line. Each line has the format:
```
session_id|hex_encoded_frame
```
- `session_id`: A string identifier grouping related packets into a single session or flow (e.g., `sess_001`).
- `hex_encoded_frame`: A raw Ethernet frame encoded as a hexadecimal string (e.g., `00112233445566778899aabb08004500...`).

## Packet Specifications

Each raw frame is a standard Ethernet II frame containing IPv4 and TCP/UDP layers:
1. **Ethernet II Header** (14 bytes):
   - Destination MAC (6 bytes), Source MAC (6 bytes), EtherType (2 bytes: `0x0800` for IPv4).
2. **IPv4 Header** (Variable length, minimum 20 bytes):
   - Version & IHL (1 byte: IHL gives header length in 32-bit words).
   - Total Length (2 bytes), Protocol (1 byte: `0x06` for TCP, `0x11` for UDP).
   - Source IP (4 bytes), Destination IP (4 bytes).
3. **TCP Header** (Variable length, minimum 20 bytes when Protocol = 6):
   - Source Port (2 bytes), Destination Port (2 bytes).
   - Sequence Number (4 bytes), Acknowledgment Number (4 bytes).
   - Data Offset & Flags (2 bytes: Data Offset gives TCP header length in 32-bit words, Flags include SYN=`0x02`, ACK=`0x10`, FIN=`0x01`, RST=`0x04`).
   - Payload follows after `Data Offset * 4` bytes.
4. **UDP Header** (8 bytes when Protocol = 17):
   - Source Port (2 bytes), Destination Port (2 bytes: Port `53` for DNS), Length (2 bytes), Checksum (2 bytes).
   - Payload follows immediately after 8 bytes.

## Classification Rules

For each unique `session_id`, analyze all associated packets and classify the session into EXACTLY ONE of the following 5 labels:

1. **`BENIGN`**: Normal HTTP/TCP traffic. Complete TCP 3-way handshake (SYN -> SYN-ACK -> ACK), standard HTTP GET/POST requests and 200 OK responses.
2. **`SYN_FLOOD`**: A high volume of TCP SYN packets sent to a target IP/port with **NO** corresponding SYN-ACK or ACK responses completed.
3. **`PORT_SCAN`**: Traffic from a single source IP probing sequential or rapidly changing destination ports on a target IP in short succession.
4. **`DNS_TUNNEL`**: UDP packets to/from port 53 where DNS query names contain unusually long subdomains (e.g., `a1b2c3d4e5f6g7h8...example.com`) used for covert data exfiltration.
5. **`SLOWLORIS`**: Multiple TCP connections sending partial HTTP request headers (e.g., sending `X-a: b\r\n` periodically) while deliberately avoiding the closing `\r\n\r\n` delimiter to exhaust server connection pools.

## Output Format

Your script `solution.py` must define a class `PacketForensics`:
```python
class PacketForensics:
    def analyze(self, filepath: str) -> dict:
        # filepath: path to packets.hex
        # returns dict mapping session_id -> classification string
        # e.g., {'sess_01': 'BENIGN', 'sess_02': 'SYN_FLOOD', ...}
        pass
```

When run as a standalone script (`python3 solution.py`), it must process `tests/packets.hex` and save the classification dictionary as a JSON object to `/src/classifications.json`.

## Requirements & Constraints
- You may use **Python standard library** only (`struct`, `json`, `os`, `sys`, `socket`).
- **NO third-party packet analysis libraries** (e.g., `scapy`, `dpkt`, `pyshark` are strictly forbidden).
- You must handle variable header lengths (IHL in IPv4, Data Offset in TCP).
- Every single session must be correctly classified to pass.
