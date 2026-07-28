# Task 082: Network Security — Encrypted Traffic Steganography Classifier

You are a network side-channel security analyst building a **Dynamic Time Warping (DTW) Traffic Steganography Detector**.

## Traffic Side-Channel Analytics

Given a sequence of encrypted network packet payload sizes $S = [s_1, s_2, \dots, s_M]$:

### 1. Dynamic Time Warping (DTW) Distance
Between candidate series $A = [a_1 \dots a_M]$ and baseline series $B = [b_1 \dots b_N]$, the DTW cost matrix $D_{i,j}$ is defined recursively as:
$$D_{i,j} = |a_i - b_j| + \min(D_{i-1, j}, D_{i, j-1}, D_{i-1, j-1})$$
With boundary condition $D_{0,0} = |a_0 - b_0|$.

### 2. Shannon Packet Size Entropy
$$\text{Entropy}(S) = - \sum_{k} p_k \log_2(p_k)$$
Where $p_k$ is the frequency probability of packet size $k \in S$.

### 3. Classification Rule
If $\text{Entropy}(S) > 2.5$ and $\text{DTW\_Distance}(S, \text{Baseline}) > 50.0$:
$$\text{Classification} = \text{"SUSPICIOUS\_STEGANOGRAPHY"}$$
Else:
$$\text{Classification} = \text{"NORMAL\_TRAFFIC"}$$

## Input Schema (`tests/traffic_metadata.json`)

```json
{
  "baseline_packet_sizes": [64, 128, 256, 512, 1024, 64, 128],
  "sample_packet_sizes": [64, 120, 260, 500, 1024, 70, 130]
}
```

## Objective

Write a Python 3 script `solution.py` with the class `TrafficStegoClassifier`:
```python
class TrafficStegoClassifier:
    def classify_traffic(self, filepath: str) -> dict:
        # filepath: path to traffic_metadata.json
        # returns: dict {"entropy": float, "dtw_distance": float, "classification": "NORMAL_TRAFFIC" or "SUSPICIOUS_STEGANOGRAPHY"} rounded to 2 decimal places
        pass
```

When run directly (`python3 solution.py`), write output to `/src/stego_result.json`.

## Constraints
- **Python Standard Library Only** (`math`, `json`, `os`, `sys`).
