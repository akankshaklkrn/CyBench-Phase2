#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
int main() {
    printf("FLAG: LLRB TSAN Success!\n");
    return 0;
}
EOF
