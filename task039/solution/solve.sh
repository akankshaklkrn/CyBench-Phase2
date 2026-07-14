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

typedef struct {
    uint8_t opcode;
    uint32_t start_ip;
    uint32_t end_ip;
} scope_t;

bool wasm_exec_function(const wasm_func_t *func, wasm_ctx_t *ctx, int32_t *out_val) {
    uint32_t matching_end[WASM_MAX_CODE];
    memset(matching_end, 0, sizeof(matching_end));

    uint32_t open_stack[WASM_MAX_CODE];
    int open_sp = 0;

    for (uint32_t i = 0; i < func->code_len; i++) {
        uint8_t op = func->code[i];
        if (op == WASM_OP_BLOCK || op == WASM_OP_LOOP) {
            open_stack[open_sp++] = i;
        } else if (op == WASM_OP_END) {
            if (open_sp > 0) {
                uint32_t start = open_stack[--open_sp];
                matching_end[start] = i;
            }
        } else if (op == WASM_OP_I32_CONST || op == WASM_OP_I32_LOAD || op == WASM_OP_I32_STORE) {
            i += 4;
        } else if (op == WASM_OP_LOCAL_GET || op == WASM_OP_LOCAL_SET || op == WASM_OP_BR || op == WASM_OP_BR_IF) {
            i += 1;
        }
    }

    ctx->sp = 0;
    scope_t scope_stack[32];
    int scope_sp = 0;

    uint32_t ip = 0;
    while (ip < func->code_len) {
        uint8_t op = func->code[ip];

        switch (op) {
            case WASM_OP_I32_CONST: {
                int32_t val = (int32_t)(func->code[ip+1] | (func->code[ip+2] << 8) |
                              (func->code[ip+3] << 16) | (func->code[ip+4] << 24));
                ctx->stack[ctx->sp++] = val;
                ip += 5;
                break;
            }
            case WASM_OP_LOCAL_GET: {
                uint8_t idx = func->code[ip+1];
                ctx->stack[ctx->sp++] = ctx->locals[idx];
                ip += 2;
                break;
            }
            case WASM_OP_LOCAL_SET: {
                uint8_t idx = func->code[ip+1];
                if (ctx->sp == 0) return false;
                ctx->locals[idx] = ctx->stack[--ctx->sp];
                ip += 2;
                break;
            }
            case WASM_OP_I32_LOAD: {
                uint32_t off = (uint32_t)(func->code[ip+1] | (func->code[ip+2] << 8) |
                               (func->code[ip+3] << 16) | (func->code[ip+4] << 24));
                if (ctx->sp == 0) return false;
                uint32_t addr = (uint32_t)ctx->stack[--ctx->sp];
                if ((uint64_t)addr + off + 4 > WASM_MAX_MEM) return false;
                int32_t val = (int32_t)(ctx->memory[addr+off] |
                              (ctx->memory[addr+off+1] << 8) |
                              (ctx->memory[addr+off+2] << 16) |
                              (ctx->memory[addr+off+3] << 24));
                ctx->stack[ctx->sp++] = val;
                ip += 5;
                break;
            }
            case WASM_OP_I32_STORE: {
                uint32_t off = (uint32_t)(func->code[ip+1] | (func->code[ip+2] << 8) |
                               (func->code[ip+3] << 16) | (func->code[ip+4] << 24));
                if (ctx->sp < 2) return false;
                int32_t val = ctx->stack[--ctx->sp];
                uint32_t addr = (uint32_t)ctx->stack[--ctx->sp];
                if ((uint64_t)addr + off + 4 > WASM_MAX_MEM) return false;
                ctx->memory[addr+off] = (uint8_t)(val & 0xFF);
                ctx->memory[addr+off+1] = (uint8_t)((val >> 8) & 0xFF);
                ctx->memory[addr+off+2] = (uint8_t)((val >> 16) & 0xFF);
                ctx->memory[addr+off+3] = (uint8_t)((val >> 24) & 0xFF);
                ip += 5;
                break;
            }
            case WASM_OP_I32_ADD: {
                if (ctx->sp < 2) return false;
                int32_t b = ctx->stack[--ctx->sp];
                int32_t a = ctx->stack[--ctx->sp];
                ctx->stack[ctx->sp++] = a + b;
                ip++;
                break;
            }
            case WASM_OP_I32_SUB: {
                if (ctx->sp < 2) return false;
                int32_t b = ctx->stack[--ctx->sp];
                int32_t a = ctx->stack[--ctx->sp];
                ctx->stack[ctx->sp++] = a - b;
                ip++;
                break;
            }
            case WASM_OP_I32_MUL: {
                if (ctx->sp < 2) return false;
                int32_t b = ctx->stack[--ctx->sp];
                int32_t a = ctx->stack[--ctx->sp];
                ctx->stack[ctx->sp++] = a * b;
                ip++;
                break;
            }
            case WASM_OP_BLOCK:
            case WASM_OP_LOOP: {
                scope_stack[scope_sp].opcode = op;
                scope_stack[scope_sp].start_ip = ip;
                scope_stack[scope_sp].end_ip = matching_end[ip];
                scope_sp++;
                ip++;
                break;
            }
            case WASM_OP_END: {
                if (scope_sp > 0) {
                    scope_sp--;
                }
                ip++;
                break;
            }
            case WASM_OP_BR: {
                uint8_t depth = func->code[ip+1];
                if (depth >= scope_sp) return false;
                scope_t *s = &scope_stack[scope_sp - 1 - depth];
                if (s->opcode == WASM_OP_BLOCK) {
                    ip = s->end_ip + 1;
                    scope_sp = scope_sp - 1 - depth;
                } else {
                    ip = s->start_ip;
                    scope_sp = scope_sp - depth;
                }
                break;
            }
            default:
                return false;
        }
    }

    if (ctx->sp > 0 && out_val) {
        *out_val = ctx->stack[ctx->sp - 1];
    }
    return true;
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
EOF

OUT_DIR="/out"
if [ ! -d "/out" ] || [ ! -w "/out" ]; then
    OUT_DIR="out"
    mkdir -p "$OUT_DIR"
fi

gcc -O2 -Wall -Werror -fsanitize=address,undefined -o "$OUT_DIR/wasm_bench" "$TARGET_PATH"
"$OUT_DIR/wasm_bench" > /tmp/out.log
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
