#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

extern void get_payload(uint8_t** payload, size_t* size);

#define OP_LOAD_IMM 0
#define OP_ADD_IMM 1
#define OP_OR_IMM 2
#define OP_LOAD_MEM 3
#define OP_EXIT 4

typedef struct {
    uint8_t opcode;
    uint8_t dst;
    uint8_t imm;
} Instruction;

typedef struct {
    uint8_t max_val;
} RegBounds;

int verify(Instruction* insts, size_t count) {
    RegBounds bounds[4] = {{0}, {0}, {0}, {0}};

    for (size_t i = 0; i < count; i++) {
        Instruction inst = insts[i];
        if (inst.dst >= 4) return 0; // Invalid register

        switch (inst.opcode) {
            case OP_LOAD_IMM:
                bounds[inst.dst].max_val = inst.imm;
                break;
            case OP_ADD_IMM:
                // Prevent verifier overflow for simplicity
                if ((uint16_t)bounds[inst.dst].max_val + inst.imm > 255) {
                    bounds[inst.dst].max_val = 255;
                } else {
                    bounds[inst.dst].max_val += inst.imm;
                }
                break;
            case OP_OR_IMM:
                // VERIFIER BUG: Incorrectly models the maximum possible value of a bitwise OR!
                bounds[inst.dst].max_val = bounds[inst.dst].max_val | inst.imm;
                break;
            case OP_LOAD_MEM:
                // Sandbox memory is 64 bytes (indices 0 to 63)
                if (bounds[inst.dst].max_val >= 64) {
                    printf("Verifier Error: Out of bounds memory access detected. Max possible index is %d\n", bounds[inst.dst].max_val);
                    return 0; // REJECT
                }
                // Memory load results in unknown value, safe conservative bound
                bounds[inst.dst].max_val = 255;
                break;
            case OP_EXIT:
                return 1; // ACCEPT
            default:
                return 0; // Unknown opcode
        }
    }
    return 1;
}

int execute(Instruction* insts, size_t count, uint8_t* sandbox, uint8_t* secret) {
    uint8_t regs[4] = {0};
    uint8_t memory[128]; // 0-63 sandbox, 64-127 secret
    
    memcpy(memory, sandbox, 64);
    memcpy(memory + 64, secret, 64);

    for (size_t i = 0; i < count; i++) {
        Instruction inst = insts[i];
        switch (inst.opcode) {
            case OP_LOAD_IMM:
                regs[inst.dst] = inst.imm;
                break;
            case OP_ADD_IMM:
                regs[inst.dst] += inst.imm;
                break;
            case OP_OR_IMM:
                regs[inst.dst] |= inst.imm;
                break;
            case OP_LOAD_MEM:
                // Runtime execution DOES NOT bounds check because verifier proved it safe!
                // This simulates JIT optimization removing bounds checks.
                regs[inst.dst] = memory[regs[inst.dst]];
                break;
            case OP_EXIT:
                return regs[0];
        }
    }
    return regs[0];
}

int main() {
    uint8_t* payload = NULL;
    size_t payload_size = 0;
    
    get_payload(&payload, &payload_size);
    
    if (!payload || payload_size % 3 != 0) {
        printf("Invalid payload size.\n");
        return 1;
    }
    
    size_t count = payload_size / 3;
    Instruction* insts = (Instruction*)payload;
    
    if (!verify(insts, count)) {
        printf("Verification Failed!\n");
        return 1;
    }
    
    uint8_t sandbox[64] = {0};
    uint8_t secret[64] = {0};
    strcpy((char*)secret, "FLAG: eBPF Verifier Bypass Success!");
    
    uint8_t result = execute(insts, count, sandbox, secret);
    printf("VM Exit Code: %c\n", result);
    
    return 0;
}
