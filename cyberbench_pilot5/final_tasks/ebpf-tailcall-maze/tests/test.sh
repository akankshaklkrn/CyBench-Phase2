#!/usr/bin/env bash
set -u
mkdir -p "${CYBERBENCH_LOG_DIR:-/logs/verifier}"
python3 "/tests/grade.py"
