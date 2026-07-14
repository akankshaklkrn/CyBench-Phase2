#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include <assert.h>

#define WASM_MAX_CODE 256
#define WASM_MAX_STACK 128
#define WASM_MAX_MEM 4096

#define WASM_OP_UNREACHABLE 0x00
#define WASM_OP_BLOCK       0x02
#define WASM_OP_LOOP        0x03
#define WASM_OP_END         0x0B
#define WASM_OP_BR          0x0C
#define WASM_OP_BR_IF       0x0D
#define WASM_OP_LOCAL_GET   0x20
#define WASM_OP_LOCAL_SET   0x21
#define WASM_OP_I32_LOAD    0x28
#define WASM_OP_I32_STORE   0x36
#define WASM_OP_I32_CONST   0x41
#define WASM_OP_I32_EQZ     0x45
#define WASM_OP_I32_ADD     0x6A
#define WASM_OP_I32_SUB     0x6B
#define WASM_OP_I32_MUL     0x6C
#define WASM_OP_I32_DIV_S   0x6D

typedef struct {
    uint8_t code[WASM_MAX_CODE];
    uint32_t code_len;
    uint32_t num_locals;
} wasm_func_t;

typedef struct {
    uint8_t memory[WASM_MAX_MEM];
    int32_t locals[16];
    int32_t stack[WASM_MAX_STACK];
    int32_t sp;
} wasm_ctx_t;

bool wasm_exec_function(const wasm_func_t *func, wasm_ctx_t *ctx, int32_t *out_val) {
    return false;
}

static void emit_u8(wasm_func_t *f, uint8_t b) {
    assert(f->code_len < WASM_MAX_CODE);
    f->code[f->code_len++] = b;
}

static void emit_u32(wasm_func_t *f, uint32_t v) {
    emit_u8(f, (uint8_t)(v & 0xFF));
    emit_u8(f, (uint8_t)((v >> 8) & 0xFF));
    emit_u8(f, (uint8_t)((v >> 16) & 0xFF));
    emit_u8(f, (uint8_t)((v >> 24) & 0xFF));
}

static void emit_i32(wasm_func_t *f, int32_t v) {
    emit_u32(f, (uint32_t)v);
}

int main() {
    printf("Starting WebAssembly Structured Control Flow Interpreter Verification under ASAN...\n");

    uint64_t state_hash = 0x93a4b7f1c2d8e5a0ULL;
    int tests_passed = 0;

    /* Test 1: Simple Arithmetic (5 + 10 * 3 = 35) */
    {
        wasm_func_t f;
        memset(&f, 0, sizeof(f));
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 5);
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 10);
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 3);
        emit_u8(&f, WASM_OP_I32_MUL);
        emit_u8(&f, WASM_OP_I32_ADD);
        emit_u8(&f, WASM_OP_END);

        wasm_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
        int32_t out = 0;
        if (wasm_exec_function(&f, &ctx, &out)) {
            tests_passed++;
            state_hash ^= ((uint64_t)(uint32_t)out * 0x1000193ULL);
            state_hash = (state_hash << 13) | (state_hash >> 51);
        } else {
            printf("FAIL: Test 1 (Arithmetic) failed execution\n");
            return 1;
        }
    }

    /* Test 2: Local Variables */
    {
        wasm_func_t f;
        memset(&f, 0, sizeof(f));
        f.num_locals = 2;
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 42);
        emit_u8(&f, WASM_OP_LOCAL_SET); emit_u8(&f, 0);
        emit_u8(&f, WASM_OP_LOCAL_GET); emit_u8(&f, 0);
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 8);
        emit_u8(&f, WASM_OP_I32_ADD);
        emit_u8(&f, WASM_OP_END);

        wasm_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
        int32_t out = 0;
        if (wasm_exec_function(&f, &ctx, &out)) {
            tests_passed++;
            state_hash ^= ((uint64_t)(uint32_t)out * 0x31337ULL);
            state_hash = (state_hash << 17) | (state_hash >> 47);
        } else {
            printf("FAIL: Test 2 (Locals) failed execution\n");
            return 1;
        }
    }

    /* Test 3: Block & Forward Branch */
    {
        wasm_func_t f;
        memset(&f, 0, sizeof(f));
        emit_u8(&f, WASM_OP_BLOCK);
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 99);
        emit_u8(&f, WASM_OP_BR); emit_u8(&f, 0);
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 1000);
        emit_u8(&f, WASM_OP_I32_ADD);
        emit_u8(&f, WASM_OP_END);
        emit_u8(&f, WASM_OP_END);

        wasm_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
        int32_t out = 0;
        if (wasm_exec_function(&f, &ctx, &out)) {
            tests_passed++;
            state_hash ^= ((uint64_t)(uint32_t)out * 0xbf58476d1ce4e5b9ULL);
            state_hash = (state_hash << 19) | (state_hash >> 45);
        } else {
            printf("FAIL: Test 3 (Block Branch) failed execution\n");
            return 1;
        }
    }

    /* Test 4: Linear Memory Store & Load */
    {
        wasm_func_t f;
        memset(&f, 0, sizeof(f));
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 128); // addr
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 777); // value
        emit_u8(&f, WASM_OP_I32_STORE); emit_u32(&f, 0);   // store at 128
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 128);
        emit_u8(&f, WASM_OP_I32_LOAD);  emit_u32(&f, 0);   // load from 128
        emit_u8(&f, WASM_OP_END);

        wasm_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
        int32_t out = 0;
        if (wasm_exec_function(&f, &ctx, &out)) {
            tests_passed++;
            state_hash ^= ((uint64_t)(uint32_t)out * 0x94d049bb133111ebULL);
            state_hash = (state_hash << 23) | (state_hash >> 41);
        } else {
            printf("FAIL: Test 4 (Memory Load/Store) failed execution\n");
            return 1;
        }
    }

    /* Test 5: Out of Bounds Memory Load Trap (Must return false) */
    {
        wasm_func_t f;
        memset(&f, 0, sizeof(f));
        emit_u8(&f, WASM_OP_I32_CONST); emit_i32(&f, 4094); // addr
        emit_u8(&f, WASM_OP_I32_LOAD);  emit_u32(&f, 4);    // addr + offset = 4098 > 4096
        emit_u8(&f, WASM_OP_END);

        wasm_ctx_t ctx; memset(&ctx, 0, sizeof(ctx));
        int32_t out = 0;
        if (!wasm_exec_function(&f, &ctx, &out)) {
            tests_passed++;
            state_hash ^= 0x1122334455667788ULL;
        } else {
            printf("FAIL: Test 5 (OOB Trap) failed to trap\n");
            return 1;
        }
    }

    if (tests_passed != 5) {
        printf("FAIL: Not all tests passed (%d/5)\n", tests_passed);
        return 1;
    }

    printf("Verification SUCCESS! Dynamic State Hash computed over %d WASM execution tests.\n", tests_passed);
    printf("cyberbench{wasm_interpreter_state_%016lx}\n", (unsigned long)state_hash);
    return 0;
}
