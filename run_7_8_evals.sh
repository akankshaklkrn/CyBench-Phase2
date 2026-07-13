#!/bin/bash
source /Users/jatinjena/Downloads/tasknew/.venv/bin/activate
export OPENROUTER_API_KEY=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

echo "Starting evaluation for task007..."
harbor run --path task007 --agent terminus-2 --model openrouter/google/gemini-3.1-pro-preview --force-build

echo "Starting evaluation for task008..."
harbor run --path task008 --agent terminus-2 --model openrouter/google/gemini-3.1-pro-preview --force-build

echo "=== All evaluations completed ==="
