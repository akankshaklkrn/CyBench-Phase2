#!/bin/sh
set -eu
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "/tests/grade_flags.py" ]; then
    python3 /tests/grade_flags.py
else
    python3 "$SCRIPT_DIR/grade_flags.py"
fi
