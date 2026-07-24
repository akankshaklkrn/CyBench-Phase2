#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
int main() {
    printf("FLAG: Hazard Engine ASAN Success!\n");
    return 0;
}
EOF
