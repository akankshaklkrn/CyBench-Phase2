#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define BPF_MAX_REG 11
#define BPF_MAX_INSNS 64

typedef enum {
    BPF_REG_NOT_INIT = 0,
    BPF_REG_SCALAR = 1,
    BPF_REG_PTR_TO_CTX = 2,
    BPF_REG_PTR_TO_MAP_VALUE = 3,
    BPF_REG_PTR_TO_STACK = 4
} bpf_reg_type_t;

typedef struct {
    bpf_reg_type_t type;
    int64_t smin_val;
    int64_t smax_val;
    uint32_t map_value_size;
    int64_t ptr_offset;
} bpf_reg_state_t;

typedef struct {
    bpf_reg_state_t regs[BPF_MAX_REG];
    uint8_t stack_init[512];
} bpf_verifier_state_t;

typedef enum {
    BPF_OP_MOV = 0,
    BPF_OP_ADD = 1,
    BPF_OP_SUB = 2,
    BPF_OP_LDX = 3,
    BPF_OP_STX = 4,
    BPF_OP_JEQ = 5,
    BPF_OP_JGT = 6,
    BPF_OP_EXIT = 7
} bpf_opcode_t;

typedef struct {
    bpf_opcode_t opcode;
    uint8_t dst_reg;
    uint8_t src_reg;
    int16_t off;
    int64_t imm;
    uint32_t map_size_meta;
} bpf_insn_t;

void bpf_init_state(bpf_verifier_state_t *st) {
    if (!st) return;
    memset(st, 0, sizeof(bpf_verifier_state_t));
    st->regs[1].type = BPF_REG_PTR_TO_CTX;
    st->regs[10].type = BPF_REG_PTR_TO_STACK;
}

int bpf_check_reg_read(const bpf_verifier_state_t *st, uint8_t regno) {
    if (!st || regno >= BPF_MAX_REG) return -1;
    if (st->regs[regno].type == BPF_REG_NOT_INIT) return -1;
    return 0;
}

int bpf_verify_alu(bpf_verifier_state_t *st, const bpf_insn_t *insn) {
    if (!st || !insn) return -1;
    if (insn->dst_reg >= BPF_MAX_REG || insn->dst_reg == 10) return -1;

    if (insn->opcode == BPF_OP_MOV) {
        if (insn->src_reg < BPF_MAX_REG) {
            if (bpf_check_reg_read(st, insn->src_reg) < 0) return -1;
            st->regs[insn->dst_reg] = st->regs[insn->src_reg];
        } else if (insn->src_reg == 255) {
            st->regs[insn->dst_reg].type = BPF_REG_SCALAR;
            st->regs[insn->dst_reg].smin_val = insn->imm;
            st->regs[insn->dst_reg].smax_val = insn->imm;
            st->regs[insn->dst_reg].ptr_offset = 0;
        } else if (insn->src_reg == 254) {
            st->regs[insn->dst_reg].type = BPF_REG_PTR_TO_MAP_VALUE;
            st->regs[insn->dst_reg].map_value_size = insn->map_size_meta;
            st->regs[insn->dst_reg].ptr_offset = insn->imm;
            st->regs[insn->dst_reg].smin_val = 0;
            st->regs[insn->dst_reg].smax_val = 0;
        } else {
            return -1;
        }
        return 0;
    }

    if (insn->opcode == BPF_OP_ADD || insn->opcode == BPF_OP_SUB) {
        bpf_reg_state_t *dst = &st->regs[insn->dst_reg];
        if (dst->type == BPF_REG_NOT_INIT) return -1;

        int64_t op_val = 0;
        bpf_reg_type_t op_type = BPF_REG_SCALAR;
        if (insn->src_reg < BPF_MAX_REG) {
            if (bpf_check_reg_read(st, insn->src_reg) < 0) return -1;
            op_type = st->regs[insn->src_reg].type;
            op_val = st->regs[insn->src_reg].smin_val;
        } else if (insn->src_reg == 255) {
            op_type = BPF_REG_SCALAR;
            op_val = insn->imm;
        } else {
            return -1;
        }

        if (dst->type == BPF_REG_PTR_TO_MAP_VALUE || dst->type == BPF_REG_PTR_TO_STACK || dst->type == BPF_REG_PTR_TO_CTX) {
            if (op_type != BPF_REG_SCALAR) return -2;
            if (insn->opcode == BPF_OP_ADD) dst->ptr_offset += op_val;
            else dst->ptr_offset -= op_val;

            if (dst->type == BPF_REG_PTR_TO_MAP_VALUE) {
                if (dst->ptr_offset < 0 || dst->ptr_offset >= (int64_t)dst->map_value_size) return -3;
            }
        } else if (dst->type == BPF_REG_SCALAR) {
            if (op_type != BPF_REG_SCALAR) return -2;
            if (insn->opcode == BPF_OP_ADD) {
                dst->smin_val += op_val;
                dst->smax_val += op_val;
            } else {
                dst->smin_val -= op_val;
                dst->smax_val -= op_val;
            }
        } else {
            return -1;
        }
        return 0;
    }

    return -1;
}

int bpf_verify_mem(bpf_verifier_state_t *st, const bpf_insn_t *insn) {
    if (!st || !insn) return -1;

    if (insn->opcode == BPF_OP_LDX) {
        if (insn->dst_reg >= 10) return -1;
        if (bpf_check_reg_read(st, insn->src_reg) < 0) return -1;

        bpf_reg_state_t *src = &st->regs[insn->src_reg];
        int64_t e_off = src->ptr_offset + insn->off;

        if (src->type == BPF_REG_PTR_TO_MAP_VALUE) {
            if (e_off < 0 || e_off + 8 > (int64_t)src->map_value_size) return -3;
            st->regs[insn->dst_reg].type = BPF_REG_SCALAR;
            st->regs[insn->dst_reg].smin_val = 0;
            st->regs[insn->dst_reg].smax_val = 0;
            st->regs[insn->dst_reg].ptr_offset = 0;
            return 0;
        } else if (src->type == BPF_REG_PTR_TO_CTX) {
            if (e_off < 0 || e_off + 8 > 64) return -3;
            st->regs[insn->dst_reg].type = BPF_REG_SCALAR;
            st->regs[insn->dst_reg].smin_val = 0;
            st->regs[insn->dst_reg].smax_val = 0;
            st->regs[insn->dst_reg].ptr_offset = 0;
            return 0;
        } else if (src->type == BPF_REG_PTR_TO_STACK) {
            if (e_off < -512 || e_off + 8 > 0) return -3;
            for (int i = 0; i < 8; i++) {
                if (st->stack_init[512 + e_off + i] == 0) return -4;
            }
            st->regs[insn->dst_reg].type = BPF_REG_SCALAR;
            st->regs[insn->dst_reg].smin_val = 0;
            st->regs[insn->dst_reg].smax_val = 0;
            st->regs[insn->dst_reg].ptr_offset = 0;
            return 0;
        } else {
            return -5;
        }
    } else if (insn->opcode == BPF_OP_STX) {
        if (insn->dst_reg >= BPF_MAX_REG) return -1;
        if (bpf_check_reg_read(st, insn->dst_reg) < 0 || bpf_check_reg_read(st, insn->src_reg) < 0) return -1;

        bpf_reg_state_t *dst = &st->regs[insn->dst_reg];
        bpf_reg_state_t *src = &st->regs[insn->src_reg];
        int64_t e_off = dst->ptr_offset + insn->off;

        if (dst->type == BPF_REG_PTR_TO_MAP_VALUE || dst->type == BPF_REG_PTR_TO_CTX) {
            if (dst->type == BPF_REG_PTR_TO_MAP_VALUE) {
                if (e_off < 0 || e_off + 8 > (int64_t)dst->map_value_size) return -3;
            } else {
                if (e_off < 0 || e_off + 8 > 64) return -3;
            }
            if (src->type != BPF_REG_SCALAR) return -6;
            return 0;
        } else if (dst->type == BPF_REG_PTR_TO_STACK) {
            if (e_off < -512 || e_off + 8 > 0) return -3;
            for (int i = 0; i < 8; i++) {
                st->stack_init[512 + e_off + i] = 1;
            }
            return 0;
        } else {
            return -5;
        }
    }

    return -1;
}

int bpf_verify_prog(const bpf_insn_t *insns, int num_insns) {
    if (!insns || num_insns <= 0 || num_insns > BPF_MAX_INSNS) return -7;
    bpf_verifier_state_t st;
    bpf_init_state(&st);

    for (int pc = 0; pc < num_insns; pc++) {
        const bpf_insn_t *insn = &insns[pc];
        switch (insn->opcode) {
            case BPF_OP_MOV:
            case BPF_OP_ADD:
            case BPF_OP_SUB: {
                int res = bpf_verify_alu(&st, insn);
                if (res < 0) return res;
                break;
            }
            case BPF_OP_LDX:
            case BPF_OP_STX: {
                int res = bpf_verify_mem(&st, insn);
                if (res < 0) return res;
                break;
            }
            case BPF_OP_JEQ:
            case BPF_OP_JGT: {
                if (bpf_check_reg_read(&st, insn->dst_reg) < 0) return -1;
                int target_pc = pc + 1 + insn->off;
                if (target_pc < 0 || target_pc >= num_insns) return -7;
                break;
            }
            case BPF_OP_EXIT: {
                if (bpf_check_reg_read(&st, 0) < 0) return -1;
                if (st.regs[0].type != BPF_REG_SCALAR) return -8;
                return 0;
            }
            default:
                return -7;
        }
    }
    return -9;
}

// Verification Harness
int main() {
    uint64_t state_hash = 0x100000001B3ULL;

    // Test 1: Valid Program (load ctx, store/load stack, map lookup simulate, exit)
    bpf_insn_t prog1[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 2, .src_reg = 255, .imm = 42 },
        { .opcode = BPF_OP_STX, .dst_reg = 10, .src_reg = 2, .off = -8 },
        { .opcode = BPF_OP_LDX, .dst_reg = 3, .src_reg = 10, .off = -8 },
        { .opcode = BPF_OP_MOV, .dst_reg = 4, .src_reg = 254, .imm = 0, .map_size_meta = 32 },
        { .opcode = BPF_OP_STX, .dst_reg = 4, .src_reg = 3, .off = 0 },
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 255, .imm = 0 },
        { .opcode = BPF_OP_EXIT }
    };
    int r1 = bpf_verify_prog(prog1, 7);
    state_hash ^= r1 * 0x1111ULL + 0xABCULL;

    // Test 2: Uninitialized Register Read (r3 read before init)
    bpf_insn_t prog2[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 3 },
        { .opcode = BPF_OP_EXIT }
    };
    int r2 = bpf_verify_prog(prog2, 2);
    state_hash ^= r2 * 0x2222ULL + 0xDEFULL;

    // Test 3: Out-of-Bounds Map Value Access (offset 32 when map size is 32 -> +8 out of bounds)
    bpf_insn_t prog3[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 4, .src_reg = 254, .imm = 0, .map_size_meta = 32 },
        { .opcode = BPF_OP_MOV, .dst_reg = 2, .src_reg = 255, .imm = 100 },
        { .opcode = BPF_OP_STX, .dst_reg = 4, .src_reg = 2, .off = 32 },
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 255, .imm = 0 },
        { .opcode = BPF_OP_EXIT }
    };
    int r3 = bpf_verify_prog(prog3, 5);
    state_hash ^= r3 * 0x3333ULL + 0x123ULL;

    // Test 4: Uninitialized Stack Read (read stack -16 without storing first)
    bpf_insn_t prog4[] = {
        { .opcode = BPF_OP_LDX, .dst_reg = 2, .src_reg = 10, .off = -16 },
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 255, .imm = 0 },
        { .opcode = BPF_OP_EXIT }
    };
    int r4 = bpf_verify_prog(prog4, 3);
    state_hash ^= r4 * 0x4444ULL + 0x456ULL;

    // Test 5: Pointer Leak (storing stack pointer into map memory)
    bpf_insn_t prog5[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 4, .src_reg = 254, .imm = 0, .map_size_meta = 32 },
        { .opcode = BPF_OP_STX, .dst_reg = 4, .src_reg = 10, .off = 0 },
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 255, .imm = 0 },
        { .opcode = BPF_OP_EXIT }
    };
    int r5 = bpf_verify_prog(prog5, 4);
    state_hash ^= r5 * 0x5555ULL + 0x789ULL;

    // Test 6: Invalid Pointer Arithmetic (ADD two pointer registers together)
    bpf_insn_t prog6[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 4, .src_reg = 254, .imm = 0, .map_size_meta = 32 },
        { .opcode = BPF_OP_ADD, .dst_reg = 4, .src_reg = 10 },
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 255, .imm = 0 },
        { .opcode = BPF_OP_EXIT }
    };
    int r6 = bpf_verify_prog(prog6, 4);
    state_hash ^= r6 * 0x6666ULL + 0x321ULL;

    // Test 7: Invalid Return Register Type (return map pointer in r0)
    bpf_insn_t prog7[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 0, .src_reg = 254, .imm = 0, .map_size_meta = 32 },
        { .opcode = BPF_OP_EXIT }
    };
    int r7 = bpf_verify_prog(prog7, 2);
    state_hash ^= r7 * 0x7777ULL + 0x654ULL;

    // Test 8: Missing Exit Instruction Check
    bpf_insn_t prog8[] = {
        { .opcode = BPF_OP_MOV, .dst_reg = 2, .src_reg = 255, .imm = 1 }
    };
    int r8 = bpf_verify_prog(prog8, 1);
    state_hash ^= r8 * 0x8888ULL + 0x987ULL;

    if (state_hash == 0) state_hash = 0xBADCAFEULL;
    printf("Verification SUCCESS! Dynamic State Hash computed over 8 eBPF verification tests.\n");
    printf("cyberbench{ebpf_security_verifier_state_%016llx}\n", (unsigned long long)state_hash);
    return 0;
}
