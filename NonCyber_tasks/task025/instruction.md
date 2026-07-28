# Task: x86-64 Mini-JIT Bytecode Compiler

Your goal is to implement a dynamic Just-In-Time (JIT) bytecode compiler in C targeting x86-64 Linux.

In `target.c`, you are provided with a Virtual Machine bytecode specification containing 8 instruction types:
- `OP_LOAD_IMM <reg>, <imm32>`: Load a 32-bit immediate integer into virtual register `<reg>` (r0 to r3).
- `OP_ADD <reg_dst>, <reg_src>`: Add virtual register `<reg_src>` to `<reg_dst>`.
- `OP_SUB <reg_dst>, <reg_src>`: Subtract `<reg_src>` from `<reg_dst>`.
- `OP_MUL <reg_dst>, <reg_src>`: Multiply `<reg_dst>` by `<reg_src>`.
- `OP_MOV <reg_dst>, <reg_src>`: Copy value from `<reg_src>` to `<reg_dst>`.
- `OP_JMP_REL <offset8>`: Unconditional relative jump by `<offset8>` signed instruction count.
- `OP_JZ_REL <reg>, <offset8>`: Jump if `<reg>` is zero by `<offset8>` signed instruction count.
- `OP_RET <reg>`: Return the 32-bit integer value in `<reg>`.

You must implement the function `int (*jit_compile(const uint8_t *bytecode, size_t len))(void)` which:
1. Allocates a read-write-execute memory buffer using `mmap` (`PROT_READ | PROT_WRITE | PROT_EXEC`).
2. Translates each virtual bytecode instruction into exact, native x86-64 machine code instructions (calculating correct REX prefixes, ModR/M bytes, and relative jump displacements in bytes).
3. Maps virtual registers r0-r3 to native x86-64 registers (e.g., `eax`, `ecx`, `edx`, `esi`).
4. Returns a function pointer to the compiled machine code buffer.

## Requirements
- **No Interpreters**: You must emit valid x86-64 CPU instructions into executable memory and execute them natively. An interpreter switch loop will fail verification.
- **Correct Jump Displacements**: Relative bytecode jumps (`OP_JMP_REL`, `OP_JZ_REL`) must be accurately translated to native x86-64 relative branch offsets in bytes.
- **Memory Safety**: Compiled with AddressSanitizer (`-fsanitize=address`). You must not cause buffer overflows or illegal instructions (`SIGILL`, `SIGSEGV`).

When finished, compile your code using `gcc -O2 -Wall -Werror -fsanitize=address -o /out/jit_bench target.c` and verify it outputs "FLAG: x86-64 Mini-JIT Compilation Success!".
