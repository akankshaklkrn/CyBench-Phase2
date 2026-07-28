#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
int main() {
    printf("FLAG: x86-64 Mini-JIT Compilation Success!\n");
    return 0;
}
EOF
