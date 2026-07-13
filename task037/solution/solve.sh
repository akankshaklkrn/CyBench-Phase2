#!/bin/bash
set -e

if mkdir -p /src 2>/dev/null && [ -w "/src" ]; then
    TARGET_PATH="/src/target.c"
else
    mkdir -p environment 2>/dev/null || true
    TARGET_PATH="environment/target.c"
fi

cat << 'EOF' > "$TARGET_PATH"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define BPF_MAX_INSNS 256
#define BPF_MAX_STACK 512

#define BPF_MOV_IMM 0x01
#define BPF_MOV_REG 0x02
#define BPF_ADD_IMM 0x03
#define BPF_ADD_REG 0x04
#define BPF_SUB_IMM 0x05
#define BPF_SUB_REG 0x06
#define BPF_MUL_IMM 0x07
#define BPF_MUL_REG 0x08
#define BPF_DIV_IMM 0x09
#define BPF_DIV_REG 0x0A
#define BPF_LDX_MEM 0x10
#define BPF_STX_MEM 0x20
#define BPF_JEQ_IMM 0x30
#define BPF_JGT_IMM 0x31
#define BPF_JMP_A   0x40
#define BPF_EXIT    0x99

typedef struct {
    uint8_t  opcode;
    uint8_t  dst_reg;
    uint8_t  src_reg;
    int16_t  off;
    int32_t  imm;
} bpf_insn_t;

typedef struct {
    bpf_insn_t insns[BPF_MAX_INSNS];
    uint32_t   num_insns;
} bpf_prog_t;

typedef enum {
    REG_NOT_INIT = 0,
    REG_SCALAR   = 1,
    REG_PTR_CTX  = 2,
    REG_PTR_STACK = 3
} reg_type_t;

bool ebpf_verify_program(const bpf_prog_t *prog, char *err_buf, size_t err_len) {
    if (!prog || prog->num_insns == 0 || prog->num_insns > BPF_MAX_INSNS) {
        if (err_buf && err_len > 0) snprintf(err_buf, err_len, "Invalid insn count");
        return false;
    }

    reg_type_t reg_types[11];
    for (int i = 0; i < 11; i++) reg_types[i] = REG_NOT_INIT;
    reg_types[1] = REG_PTR_CTX;
    reg_types[10] = REG_PTR_STACK;

    bool has_exit = false;

    for (uint32_t pc = 0; pc < prog->num_insns; pc++) {
        const bpf_insn_t *insn = &prog->insns[pc];

        if (insn->dst_reg > 10 || insn->src_reg > 10) {
            if (err_buf && err_len > 0) snprintf(err_buf, err_len, "Register index out of bounds");
            return false;
        }

        switch (insn->opcode) {
            case BPF_MOV_IMM:
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_MOV_REG:
                if (reg_types[insn->src_reg] == REG_NOT_INIT) {
                    if (err_buf && err_len > 0) snprintf(err_buf, err_len, "Reading uninitialized src reg");
                    return false;
                }
                reg_types[insn->dst_reg] = reg_types[insn->src_reg];
                break;
            case BPF_ADD_IMM:
            case BPF_SUB_IMM:
            case BPF_MUL_IMM:
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_ADD_REG:
            case BPF_SUB_REG:
            case BPF_MUL_REG:
                if (reg_types[insn->src_reg] == REG_NOT_INIT) return false;
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_DIV_IMM:
                if (insn->imm == 0) return false;
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_DIV_REG:
                if (reg_types[insn->src_reg] == REG_NOT_INIT) return false;
                // Static verifier conservatively rejects div by reg unless proven non-zero
                // For safety challenge, require divisor scalar check
                if (insn->imm == 0) {
                    // Check if imm encodes proven non-zero
                    return false;
                }
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_LDX_MEM:
                if (insn->src_reg != 10 && insn->src_reg != 1) return false;
                if (insn->src_reg == 10) {
                    if (insn->off < -BPF_MAX_STACK || insn->off > -8 || (insn->off % 8 != 0)) return false;
                }
                reg_types[insn->dst_reg] = REG_SCALAR;
                break;
            case BPF_STX_MEM:
                if (insn->dst_reg != 10 && insn->dst_reg != 1) return false;
                if (insn->dst_reg == 10) {
                    if (insn->off < -BPF_MAX_STACK || insn->off > -8 || (insn->off % 8 != 0)) return false;
                }
                break;
            case BPF_JEQ_IMM:
            case BPF_JGT_IMM:
            case BPF_JMP_A: {
                int32_t target = (int32_t)pc + 1 + insn->off;
                if (target < 0 || target >= (int32_t)prog->num_insns) return false;
                if (insn->off < 0) return false; // reject back-edges
                break;
            }
            case BPF_EXIT:
                has_exit = true;
                break;
            default:
                return false;
        }
    }

    return has_exit;
}

bool ebpf_exec_program(const bpf_prog_t *prog, const uint8_t *ctx, size_t ctx_len, uint64_t *out_ret) {
    if (!prog || prog->num_insns == 0) return false;

    uint64_t regs[11];
    memset(regs, 0, sizeof(regs));

    uint8_t stack[BPF_MAX_STACK];
    memset(stack, 0, sizeof(stack));

    regs[1] = (uint64_t)(uintptr_t)ctx;
    regs[10] = (uint64_t)(uintptr_t)(stack + BPF_MAX_STACK);

    for (uint32_t pc = 0; pc < prog->num_insns; pc++) {
        const bpf_insn_t *insn = &prog->insns[pc];
        switch (insn->opcode) {
            case BPF_MOV_IMM:
                regs[insn->dst_reg] = insn->imm;
                break;
            case BPF_MOV_REG:
                regs[insn->dst_reg] = regs[insn->src_reg];
                break;
            case BPF_ADD_IMM:
                regs[insn->dst_reg] += insn->imm;
                break;
            case BPF_ADD_REG:
                regs[insn->dst_reg] += regs[insn->src_reg];
                break;
            case BPF_SUB_IMM:
                regs[insn->dst_reg] -= insn->imm;
                break;
            case BPF_SUB_REG:
                regs[insn->dst_reg] -= regs[insn->src_reg];
                break;
            case BPF_MUL_IMM:
                regs[insn->dst_reg] *= insn->imm;
                break;
            case BPF_MUL_REG:
                regs[insn->dst_reg] *= regs[insn->src_reg];
                break;
            case BPF_DIV_IMM:
                if (insn->imm == 0) return false;
                regs[insn->dst_reg] /= insn->imm;
                break;
            case BPF_DIV_REG:
                if (regs[insn->src_reg] == 0) return false;
                regs[insn->dst_reg] /= regs[insn->src_reg];
                break;
            case BPF_LDX_MEM: {
                uint8_t *ptr = (uint8_t *)(uintptr_t)(regs[insn->src_reg] + insn->off);
                regs[insn->dst_reg] = *(uint64_t *)ptr;
                break;
            }
            case BPF_STX_MEM: {
                uint8_t *ptr = (uint8_t *)(uintptr_t)(regs[insn->dst_reg] + insn->off);
                *(uint64_t *)ptr = regs[insn->src_reg];
                break;
            }
            case BPF_JEQ_IMM:
                if (regs[insn->dst_reg] == (uint64_t)(int64_t)insn->imm) {
                    pc += insn->off;
                }
                break;
            case BPF_JGT_IMM:
                if (regs[insn->dst_reg] > (uint64_t)(int64_t)insn->imm) {
                    pc += insn->off;
                }
                break;
            case BPF_JMP_A:
                pc += insn->off;
                break;
            case BPF_EXIT:
                if (out_ret) *out_ret = regs[0];
                return true;
            default:
                return false;
        }
    }
    return false;
}

int main() {
    printf("Starting eBPF Static Verifier & Execution Engine Verification under ASAN...\n");
    
    bpf_prog_t bad_progs[10];
    memset(bad_progs, 0, sizeof(bad_progs));
    
    bad_progs[0].num_insns = 2;
    bad_progs[0].insns[0] = (bpf_insn_t){BPF_JMP_A, 0, 0, 10, 0};
    bad_progs[0].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[1].num_insns = 3;
    bad_progs[1].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 0, 0, 0, 100};
    bad_progs[1].insns[1] = (bpf_insn_t){BPF_DIV_IMM, 0, 0, 0, 0};
    bad_progs[1].insns[2] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[2].num_insns = 2;
    bad_progs[2].insns[0] = (bpf_insn_t){BPF_MOV_REG, 0, 5, 0, 0};
    bad_progs[2].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[3].num_insns = 2;
    bad_progs[3].insns[0] = (bpf_insn_t){BPF_LDX_MEM, 0, 10, -600, 0};
    bad_progs[3].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[4].num_insns = 2;
    bad_progs[4].insns[0] = (bpf_insn_t){BPF_LDX_MEM, 0, 10, -7, 0};
    bad_progs[4].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[5].num_insns = 1;
    bad_progs[5].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 0, 0, 0, 42};
    
    bad_progs[6].num_insns = 2;
    bad_progs[6].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 0, 0, 0, 1};
    bad_progs[6].insns[1] = (bpf_insn_t){BPF_JMP_A, 0, 0, -2, 0};
    
    bad_progs[7].num_insns = 4;
    bad_progs[7].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 0, 0, 0, 50};
    bad_progs[7].insns[1] = (bpf_insn_t){BPF_MOV_IMM, 2, 0, 0, 0};
    bad_progs[7].insns[2] = (bpf_insn_t){BPF_DIV_REG, 0, 2, 0, 0};
    bad_progs[7].insns[3] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[8].num_insns = 2;
    bad_progs[8].insns[0] = (bpf_insn_t){BPF_LDX_MEM, 0, 10, 8, 0};
    bad_progs[8].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    
    bad_progs[9].num_insns = 2;
    bad_progs[9].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 11, 0, 0, 5};
    bad_progs[9].insns[1] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};

    char err[128];
    for (int i = 0; i < 10; i++) {
        err[0] = '\0';
        if (ebpf_verify_program(&bad_progs[i], err, sizeof(err))) {
            printf("FAIL: Verifier accepted invalid program %d\n", i);
            return 1;
        }
    }
    
    bpf_prog_t good_progs[10];
    memset(good_progs, 0, sizeof(good_progs));
    
    for (int i = 0; i < 10; i++) {
        good_progs[i].num_insns = 4;
        good_progs[i].insns[0] = (bpf_insn_t){BPF_MOV_IMM, 0, 0, 0, (i + 1) * 10};
        good_progs[i].insns[1] = (bpf_insn_t){BPF_ADD_IMM, 0, 0, 0, i + 5};
        good_progs[i].insns[2] = (bpf_insn_t){BPF_MUL_IMM, 0, 0, 0, 3};
        good_progs[i].insns[3] = (bpf_insn_t){BPF_EXIT, 0, 0, 0, 0};
    }
    
    uint64_t state_hash = 0x9e3779b97f4a7c15ULL;
    uint8_t dummy_ctx[64] = {0};
    
    for (int i = 0; i < 10; i++) {
        err[0] = '\0';
        if (!ebpf_verify_program(&good_progs[i], err, sizeof(err))) {
            printf("FAIL: Verifier rejected valid program %d: %s\n", i, err);
            return 1;
        }
        uint64_t ret = 0;
        if (!ebpf_exec_program(&good_progs[i], dummy_ctx, sizeof(dummy_ctx), &ret)) {
            printf("FAIL: Execution engine failed on valid program %d\n", i);
            return 1;
        }
        uint64_t expected = (((i + 1) * 10) + i + 5) * 3;
        if (ret != expected) {
            printf("FAIL: Program %d returned %llu, expected %llu\n", i, (unsigned long long)ret, (unsigned long long)expected);
            return 1;
        }
        state_hash ^= ret * 0xbf58476d1ce4e5b9ULL;
        state_hash = (state_hash << 13) | (state_hash >> 51);
    }
    
    printf("Verification SUCCESS! Dynamic State Hash computed.\n");
    printf("cyberbench{ebpf_verifier_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -fsanitize=address,undefined -o "$OUT_DIR/ebpf_bench" "$TARGET_PATH"
"$OUT_DIR/ebpf_bench" > /tmp/out.log
FLAG=$(grep -o "cyberbench{[^}]*}" /tmp/out.log || true)

if [ -n "$FLAG" ]; then
    if [ -d "/app" ] && [ -w "/app" ]; then
        echo "$FLAG" > /app/flags.txt
    else
        echo "$FLAG" > flags.txt
    fi
    echo "Oracle successfully generated dynamic flag: $FLAG"
else
    echo "Oracle failed to generate flag!"
    cat /tmp/out.log
    exit 1
fi
