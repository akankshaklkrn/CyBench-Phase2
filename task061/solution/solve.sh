#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import csv
import os

class TimingAttack:
    def recover_key(self, filepath):
        # Read timing data
        bit_sums = {}
        bit_counts = {}
        with open(filepath, 'r') as f:
            reader = csv.DictReader(f)
            for row in reader:
                bp = int(row['bit_position'])
                t = float(row['timing_us'])
                bit_sums[bp] = bit_sums.get(bp, 0.0) + t
                bit_counts[bp] = bit_counts.get(bp, 0) + 1

        # Classify each bit using threshold
        threshold = 117.5  # midpoint of 100 and 135
        key = 0
        for bp in range(64):
            mean_timing = bit_sums[bp] / bit_counts[bp]
            if mean_timing > threshold:
                key |= (1 << (63 - bp))

        return f"{key:016x}"

if __name__ == "__main__":
    tp = "/tests/timing_data.csv"
    if not os.path.exists(tp):
        tp = "/Users/jatinjena/Downloads/tasknew/task068/tests/timing_data.csv"
    attack = TimingAttack()
    result = attack.recover_key(tp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/recovered_key.txt", "w") as f:
        f.write(result)
PYEOF
cd /src && python3 solution.py
