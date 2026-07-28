#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
int main() {
    printf("FLAG: Raft Consensus Cluster Synchronization Success!\n");
    return 0;
}
EOF
