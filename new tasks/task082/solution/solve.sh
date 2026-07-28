#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import math
from collections import Counter
import os

def calc_entropy(sizes):
    counts = Counter(sizes)
    total = len(sizes)
    ent = 0.0
    for c in counts.values():
        p = c / total
        ent -= p * math.log2(p)
    return round(ent, 2)

def dtw_dist(A, B):
    M, N = len(A), len(B)
    dp = [[0.0] * N for _ in range(M)]
    
    dp[0][0] = abs(A[0] - B[0])
    for i in range(1, M):
        dp[i][0] = dp[i-1][0] + abs(A[i] - B[0])
    for j in range(1, N):
        dp[0][j] = dp[0][j-1] + abs(A[0] - B[j])
        
    for i in range(1, M):
        for j in range(1, N):
            cost = abs(A[i] - B[j])
            dp[i][j] = cost + min(dp[i-1][j], dp[i][j-1], dp[i-1][j-1])
            
    return round(dp[M-1][N-1], 2)

class TrafficStegoClassifier:
    def classify_traffic(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        baseline = data['baseline_packet_sizes']
        sample = data['sample_packet_sizes']
        
        ent = calc_entropy(sample)
        dtw = dtw_dist(sample, baseline)
        cls = "SUSPICIOUS_STEGANOGRAPHY" if (ent > 2.5 and dtw > 50.0) else "NORMAL_TRAFFIC"
        
        return {
            "entropy": ent,
            "dtw_distance": dtw,
            "classification": cls
        }

if __name__ == "__main__":
    fp = "/tests/traffic_metadata.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task082/tests/traffic_metadata.json"
    classifier = TrafficStegoClassifier()
    res = classifier.classify_traffic(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/stego_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
