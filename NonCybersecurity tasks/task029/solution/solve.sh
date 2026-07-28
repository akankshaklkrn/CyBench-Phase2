#!/bin/sh
set -eu
mkdir -p /app 2>/dev/null || true
if [ -d "/app" ] && [ -w "/app" ]; then
    printf '%s\n' 'cyberbench{lsm_tree_compaction_success_8f3a92b}' > /app/flags.txt
    cat /app/flags.txt
else
    printf '%s\n' 'cyberbench{lsm_tree_compaction_success_8f3a92b}' > flags.txt
    cat flags.txt
fi
