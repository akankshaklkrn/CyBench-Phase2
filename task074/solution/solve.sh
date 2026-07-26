#!/usr/bin/env bash
mkdir -p /src
cat << 'PYEOF' > /src/solution.py
import json
import math
import os

class DPAggregator:
    def process_dp_queries(self, filepath: str) -> dict:
        with open(filepath, 'r') as f:
            data = json.load(f)
            
        sensitivity = float(data['sensitivity'])
        max_budget = float(data['max_epsilon_budget'])
        queries = data['queries']
        
        tot_eps = sum(float(q['epsilon']) for q in queries)
        if tot_eps > max_budget:
            return {"budget_exceeded": True, "estimated_mean": 0.0, "ci_95": 0.0}
            
        sum_eps_sq = sum((float(q['epsilon']) ** 2) for q in queries)
        weighted_sum = sum(((float(q['epsilon']) ** 2) * float(q['response'])) for q in queries)
        
        est_mean = round(weighted_sum / sum_eps_sq, 4)
        ci_95 = round(1.96 * math.sqrt((2.0 * (sensitivity ** 2)) / sum_eps_sq), 4)
        
        return {
            "budget_exceeded": False,
            "estimated_mean": est_mean,
            "ci_95": ci_95
        }

if __name__ == "__main__":
    fp = "/tests/dp_queries.json"
    if not os.path.exists(fp):
        fp = "/Users/jatinjena/Downloads/tasknew/task074/tests/dp_queries.json"
    aggregator = DPAggregator()
    res = aggregator.process_dp_queries(fp)
    os.makedirs("/src", exist_ok=True)
    with open("/src/dp_result.json", "w") as f:
        json.dump(res, f, indent=2)
PYEOF
cd /src && python3 solution.py
