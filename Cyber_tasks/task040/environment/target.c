#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define EBPF_MAX_INSNS 256
#define EBPF_STACK_SIZE 512

/* eBPF Instruction Opcodes */
#define EBPF_OP_MOV64_IMM   0xB7
#define EBPF_OP_MOV64_REG   0xBF
#define EBPF_OP_ADD64_IMM   0x07
#define EBPF_OP_ADD64_REG   0x0F
#define EBPF_OP_SUB64_IMM   0x17
#define EBPF_OP_SUB64_REG   0x1F
#define EBPF_OP_DIV64_IMM   0x37
#define EBPF_OP_DIV64_REG   0x3F

#define EBPF_OP_JGT_IMM     0x25
#define EBPF_OP_JGT_REG     0x2D
#define EBPF_OP_JEQ_IMM     0x15
#define EBPF_OP_JEQ_REG     0x1D
#define EBPF_OP_EXIT        0x95

#define EBPF_OP_LDX_B       0x71
#define EBPF_OP_LDX_W       0x61
#define EBPF_OP_STX_B       0x73
#define EBPF_OP_STX_W       0x63

typedef struct {
    uint8_t opcode;
    uint8_t dst_reg;
    uint8_t src_reg;
    int16_t off;
    int32_t imm;
} ebpf_insn_t;

typedef struct {
    ebpf_insn_t insns[EBPF_MAX_INSNS];
    uint32_t len;
} ebpf_prog_t;

typedef struct {
    uint64_t regs[11];
    uint8_t stack[EBPF_STACK_SIZE];
    const uint8_t *packet_data;
    uint32_t packet_len;
} ebpf_ctx_t;

/* Abstract Verifier Implementation */
bool ebpf_verify_program(const ebpf_prog_t *prog, uint32_t max_packet_len) {
    /* TODO: Implement abstract static verification tracking register types and bounds */
    return false;
}

/* Execution Engine Implementation */
bool ebpf_exec_program(const ebpf_prog_t *prog, ebpf_ctx_t *ctx, uint64_t *out_val) {
    /* TODO: Implement safe register VM execution engine */
    return false;
}

static void emit(ebpf_prog_t *p, uint8_t op, uint8_t dst, uint8_t src, int16_t off, int32_t imm) {
    assert(p->len < EBPF_MAX_INSNS);
    ebpf_insn_t *i = &p->insns[p->len++];
    i->opcode = op;
    i->dst_reg = dst;
    i->src_reg = src;
    i->off = off;
    i->imm = imm;
}

int main(void) {
    int tests_passed = 0;
    uint64_t state_hash = 0xcafebabedeedbeefULL;

    /* Test 1: Valid Packet Header Check (data + 14 <= data_end -> safe read at data + 0) */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        /* r1 = pkt_data, r2 = pkt_end */
        emit(&p, EBPF_OP_MOV64_REG, 3, 1, 0, 0);       // r3 = data
        emit(&p, EBPF_OP_ADD64_IMM, 3, 0, 0, 14);      // r3 = data + 14
        emit(&p, EBPF_OP_JGT_REG,   3, 2, 2, 0);       // if r3 > pkt_end goto exit(0)
        emit(&p, EBPF_OP_LDX_B,     0, 1, 0, 0);       // r0 = *(uint8_t*)(data + 0)
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);       // return r0
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 0);       // r0 = 0
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        uint8_t pkt[32] = { 0x42, 0x01, 0x02 };
        if (ebpf_verify_program(&p, sizeof(pkt))) {
            ebpf_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
            ctx.regs[1] = (uint64_t)(uintptr_t)pkt;
            ctx.regs[2] = (uint64_t)(uintptr_t)(pkt + sizeof(pkt));
            uint64_t out = 0;
            if (ebpf_exec_program(&p, &ctx, &out) && out == 0x42) {
                tests_passed++;
                state_hash ^= (out * 0x100000001B3ULL);
            } else {
                printf("FAIL: Test 1 execution failed\n");
                return 1;
            }
        } else {
            printf("FAIL: Test 1 verification failed\n");
            return 1;
        }
    }

    /* Test 2: Out of Bounds Packet Read without Check (Must be rejected by verifier) */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_LDX_B, 0, 1, 100, 0);         // r0 = *(uint8_t*)(data + 100)
        emit(&p, EBPF_OP_EXIT,  0, 0, 0, 0);

        if (!ebpf_verify_program(&p, 32)) {
            tests_passed++;
            state_hash ^= 0x3333444455556666ULL;
        } else {
            printf("FAIL: Test 2 verifier failed to reject OOB packet read\n");
            return 1;
        }
    }

    /* Test 3: Invalid Pointer Arithmetic (pointer + pointer must be rejected) */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_ADD64_REG, 1, 2, 0, 0);       // r1(data) += r2(data_end) -> illegal
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        if (!ebpf_verify_program(&p, 32)) {
            tests_passed++;
            state_hash ^= 0x777788889999AAAAULL;
        } else {
            printf("FAIL: Test 3 verifier failed to reject ptr + ptr\n");
            return 1;
        }
    }

    /* Test 4: Safe Packet Modification with conditional bounds check */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_REG, 3, 1, 0, 0);
        emit(&p, EBPF_OP_ADD64_IMM, 3, 0, 0, 4);
        emit(&p, EBPF_OP_JGT_REG,   3, 2, 2, 0);
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 0x99);
        emit(&p, EBPF_OP_STX_B,     1, 0, 2, 0);       // *(data + 2) = r0
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        uint8_t pkt[16] = { 0 };
        if (ebpf_verify_program(&p, sizeof(pkt))) {
            ebpf_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
            ctx.regs[1] = (uint64_t)(uintptr_t)pkt;
            ctx.regs[2] = (uint64_t)(uintptr_t)(pkt + sizeof(pkt));
            uint64_t out = 0;
            if (ebpf_exec_program(&p, &ctx, &out) && pkt[2] == 0x99) {
                tests_passed++;
                state_hash ^= 0x1122334411223344ULL;
            } else {
                printf("FAIL: Test 4 execution failed\n");
                return 1;
            }
        } else {
            printf("FAIL: Test 4 verification failed\n");
            return 1;
        }
    }

    /* Test 5: Division by Zero Check (Immediate 0 div must be rejected) */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 100);
        emit(&p, EBPF_OP_DIV64_IMM, 0, 0, 0, 0);       // r0 /= 0
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        if (!ebpf_verify_program(&p, 32)) {
            tests_passed++;
            state_hash ^= 0xA5A5A5A55A5A5A5AULL;
        } else {
            printf("FAIL: Test 5 verifier failed to reject div-by-zero\n");
            return 1;
        }
    }

    /* Test 6: Safe Stack Scratch Memory Access (r10 - 8) */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 0x77);
        emit(&p, EBPF_OP_STX_B,     10, 0, -8, 0);     // *(fp - 8) = r0
        emit(&p, EBPF_OP_LDX_B,     0, 10, -8, 0);     // r0 = *(fp - 8)
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        if (ebpf_verify_program(&p, 32)) {
            ebpf_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
            ctx.regs[10] = (uint64_t)(uintptr_t)(ctx.stack + EBPF_STACK_SIZE);
            uint64_t out = 0;
            if (ebpf_exec_program(&p, &ctx, &out) && out == 0x77) {
                tests_passed++;
                state_hash ^= (out * 0x987654321ULL);
            } else {
                printf("FAIL: Test 6 execution failed\n");
                return 1;
            }
        } else {
            printf("FAIL: Test 6 verification failed\n");
            return 1;
        }
    }

    if (tests_passed != 6) {
        printf("FAIL: Not all tests passed (%d/6)\n", tests_passed);
        return 1;
    }

    printf("Verification SUCCESS! Dynamic State Hash computed over %d eBPF verification tests.\n", tests_passed);
    printf("cyberbench{ebpf_verifier_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
