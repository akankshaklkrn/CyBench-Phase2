#!/bin/bash
set -e

export OPENROUTER_API_KEY="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"
HARBOR="/Users/jatinjena/Downloads/tasknew/.venv/bin/harbor"

mkdir -p runs/gemini-3.1-pro-preview

echo "Starting CyBench Gemini Evaluations for Tasks 051 to 053..."

for TASK_NAME in task051 task052 task053; do
    echo "==========================================================="
    echo "Running Gemini evaluation on $TASK_NAME..."
    echo "==========================================================="
    
    $HARBOR run \
        --path "$TASK_NAME" \
        --agent terminus-2 \
        --model openrouter/google/gemini-3.1-pro-preview \
        --force-build || true
        
    LATEST_JOB=$(ls -t jobs/ 2>/dev/null | head -1 || true)
    if [ -n "$LATEST_JOB" ] && [ -d "jobs/$LATEST_JOB" ]; then
        rm -rf "runs/gemini-3.1-pro-preview/$TASK_NAME"
        cp -r "jobs/$LATEST_JOB" "runs/gemini-3.1-pro-preview/$TASK_NAME"
        echo "DONE: $TASK_NAME saved to runs/gemini-3.1-pro-preview/$TASK_NAME"
    fi
    sleep 2
done

echo "==========================================================="
echo "All tasks completed! Summary of Results:"
echo "==========================================================="

for TASK_NAME in task051 task052 task053; do
    RESULT_JSON="runs/gemini-3.1-pro-preview/$TASK_NAME/result.json"
    if [ -f "$RESULT_JSON" ]; then
        echo -n "$TASK_NAME: "
        python3 -c "
import sys, json
try:
    d = json.load(open('$RESULT_JSON'))
    evals = list(d['stats']['evals'].values())
    print('reward:', evals[0]['metrics'][0]['mean']) if evals else print('empty')
except Exception as e:
    print('error checking result:', e)
"
    else
        echo "$TASK_NAME: No result.json found"
    fi
done
