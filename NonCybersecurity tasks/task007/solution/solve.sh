#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
int main() {
    return 0;
}
EOF
