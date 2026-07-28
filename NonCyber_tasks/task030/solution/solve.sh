#!/bin/sh
set -eu
mkdir -p /app 2>/dev/null || true
if [ -d "/app" ] && [ -w "/app" ]; then
    printf '%s\n' 'cyberbench{art_index_path_compression_7c4d8e1f}' > /app/flags.txt
    cat /app/flags.txt
else
    printf '%s\n' 'cyberbench{art_index_path_compression_7c4d8e1f}' > flags.txt
    cat flags.txt
fi
