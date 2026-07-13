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

bool ebpf_verify_program(const bpf_prog_t *prog, char *err_buf, size_t err_len) {
    return false;
}

bool ebpf_exec_program(const bpf_prog_t *prog, const uint8_t *ctx, size_t ctx_len, uint64_t *out_ret) {
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
