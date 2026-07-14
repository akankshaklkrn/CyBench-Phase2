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

typedef enum {
    REG_UNINIT = 0,
    REG_SCALAR,
    REG_PTR_PACKET,
    REG_PTR_PACKET_END,
    REG_PTR_STACK
} reg_type_t;

typedef struct {
    reg_type_t type;
    int64_t min_val;
    int64_t max_val;
    int64_t pkt_off;
} reg_state_t;

bool ebpf_verify_program(const ebpf_prog_t *prog, uint32_t max_packet_len) {
    if (prog->len == 0 || prog->len > EBPF_MAX_INSNS) return false;
    reg_state_t regs[11];
    memset(regs, 0, sizeof(regs));
    
    regs[1].type = REG_PTR_PACKET;
    regs[1].pkt_off = 0;
    regs[2].type = REG_PTR_PACKET_END;
    regs[2].pkt_off = max_packet_len;
    regs[10].type = REG_PTR_STACK;

    uint32_t pc = 0;
    while (pc < prog->len) {
        const ebpf_insn_t *insn = &prog->insns[pc];
        uint8_t dst = insn->dst_reg;
        uint8_t src = insn->src_reg;
        if (dst >= 11 || src >= 11) return false;

        switch (insn->opcode) {
            case EBPF_OP_MOV64_IMM:
                if (dst == 10) return false;
                regs[dst].type = REG_SCALAR;
                regs[dst].min_val = insn->imm;
                regs[dst].max_val = insn->imm;
                break;
            case EBPF_OP_MOV64_REG:
                if (dst == 10) return false;
                regs[dst] = regs[src];
                break;
            case EBPF_OP_ADD64_IMM:
                if (dst == 10) return false;
                if (regs[dst].type == REG_PTR_PACKET) {
                    regs[dst].pkt_off += insn->imm;
                } else if (regs[dst].type == REG_SCALAR) {
                    regs[dst].min_val += insn->imm;
                    regs[dst].max_val += insn->imm;
                } else return false;
                break;
            case EBPF_OP_ADD64_REG:
                if (dst == 10) return false;
                if (regs[dst].type != REG_SCALAR && regs[src].type != REG_SCALAR) {
                    return false; // ptr + ptr illegal
                }
                break;
            case EBPF_OP_DIV64_IMM:
                if (dst == 10) return false;
                if (insn->imm == 0) return false;
                regs[dst].type = REG_SCALAR;
                break;
            case EBPF_OP_LDX_B:
            case EBPF_OP_LDX_W: {
                if (dst == 10) return false;
                if (regs[src].type == REG_PTR_PACKET) {
                    int64_t eff = regs[src].pkt_off + insn->off;
                    int size = (insn->opcode == EBPF_OP_LDX_B) ? 1 : 4;
                    if (eff < 0 || eff + size > max_packet_len) return false;
                } else if (regs[src].type == REG_PTR_STACK) {
                    if (insn->off < -EBPF_STACK_SIZE || insn->off >= 0) return false;
                } else {
                    return false;
                }
                regs[dst].type = REG_SCALAR;
                break;
            }
            case EBPF_OP_STX_B:
            case EBPF_OP_STX_W: {
                if (regs[dst].type == REG_PTR_PACKET) {
                    int64_t eff = regs[dst].pkt_off + insn->off;
                    int size = (insn->opcode == EBPF_OP_STX_B) ? 1 : 4;
                    if (eff < 0 || eff + size > max_packet_len) return false;
                } else if (regs[dst].type == REG_PTR_STACK) {
                    if (insn->off < -EBPF_STACK_SIZE || insn->off >= 0) return false;
                } else {
                    return false;
                }
                break;
            }
            case EBPF_OP_JGT_REG:
            case EBPF_OP_JEQ_REG:
            case EBPF_OP_JGT_IMM:
            case EBPF_OP_JEQ_IMM:
                pc += insn->off;
                break;
            case EBPF_OP_EXIT:
                return true;
            default:
                break;
        }
        pc++;
    }
    return true;
}

bool ebpf_exec_program(const ebpf_prog_t *prog, ebpf_ctx_t *ctx, uint64_t *out_val) {
    uint32_t pc = 0;
    while (pc < prog->len) {
        const ebpf_insn_t *insn = &prog->insns[pc];
        uint8_t dst = insn->dst_reg;
        uint8_t src = insn->src_reg;

        switch (insn->opcode) {
            case EBPF_OP_MOV64_IMM:
                ctx->regs[dst] = (int64_t)insn->imm;
                break;
            case EBPF_OP_MOV64_REG:
                ctx->regs[dst] = ctx->regs[src];
                break;
            case EBPF_OP_ADD64_IMM:
                ctx->regs[dst] += (int64_t)insn->imm;
                break;
            case EBPF_OP_ADD64_REG:
                ctx->regs[dst] += ctx->regs[src];
                break;
            case EBPF_OP_DIV64_IMM:
                if (insn->imm == 0) return false;
                ctx->regs[dst] /= insn->imm;
                break;
            case EBPF_OP_LDX_B: {
                uintptr_t addr = (uintptr_t)ctx->regs[src] + insn->off;
                ctx->regs[dst] = *(uint8_t*)addr;
                break;
            }
            case EBPF_OP_STX_B: {
                uintptr_t addr = (uintptr_t)ctx->regs[dst] + insn->off;
                *(uint8_t*)addr = (uint8_t)ctx->regs[src];
                break;
            }
            case EBPF_OP_JGT_REG:
                if (ctx->regs[dst] > ctx->regs[src]) {
                    pc += insn->off;
                }
                break;
            case EBPF_OP_EXIT:
                *out_val = ctx->regs[0];
                return true;
            default:
                break;
        }
        pc++;
    }
    return true;
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

    /* Test 1: Valid Packet Header Check */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_REG, 3, 1, 0, 0);
        emit(&p, EBPF_OP_ADD64_IMM, 3, 0, 0, 14);
        emit(&p, EBPF_OP_JGT_REG,   3, 2, 2, 0);
        emit(&p, EBPF_OP_LDX_B,     0, 1, 0, 0);
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 0);
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

    /* Test 2: Out of Bounds Packet Read without Check */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_LDX_B, 0, 1, 100, 0);
        emit(&p, EBPF_OP_EXIT,  0, 0, 0, 0);

        if (!ebpf_verify_program(&p, 32)) {
            tests_passed++;
            state_hash ^= 0x3333444455556666ULL;
        } else {
            printf("FAIL: Test 2 verifier failed to reject OOB packet read\n");
            return 1;
        }
    }

    /* Test 3: Invalid Pointer Arithmetic */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_ADD64_REG, 1, 2, 0, 0);
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
        emit(&p, EBPF_OP_STX_B,     1, 0, 2, 0);
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

    /* Test 5: Division by Zero Check */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 100);
        emit(&p, EBPF_OP_DIV64_IMM, 0, 0, 0, 0);
        emit(&p, EBPF_OP_EXIT,      0, 0, 0, 0);

        if (!ebpf_verify_program(&p, 32)) {
            tests_passed++;
            state_hash ^= 0xA5A5A5A55A5A5A5AULL;
        } else {
            printf("FAIL: Test 5 verifier failed to reject div-by-zero\n");
            return 1;
        }
    }

    /* Test 6: Safe Stack Scratch Memory Access */
    {
        ebpf_prog_t p; memset(&p, 0, sizeof(p));
        emit(&p, EBPF_OP_MOV64_IMM, 0, 0, 0, 0x77);
        emit(&p, EBPF_OP_STX_B,     10, 0, -8, 0);
        emit(&p, EBPF_OP_LDX_B,     0, 10, -8, 0);
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
