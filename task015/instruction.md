# Task: Strict JSON AST Parser with AddressSanitizer

Your goal is to write a JSON string parser in C from scratch.

In `target.c`, you are given standard structs for a JSON Abstract Syntax Tree (AST), including Arrays, Objects, Strings, and Numbers.
You must implement `parse_json(const char *json)` and `free_json(json_node *node)`.

## Requirements
1. **Dynamic AST Allocation**: You must dynamically allocate memory for nodes, strings, and object keys as you parse the raw JSON string.
2. **Strict Memory Safety (ASAN)**: This program will be compiled with `-fsanitize=address`. AddressSanitizer will abort the program if you leak a *single byte* of memory, read past the end of a buffer, or trigger a use-after-free.
3. **Recursive Freeing**: Your `free_json` function must recursively and perfectly free the entire AST.

The stress test will pass a massive, deeply nested JSON string containing arrays, objects, and strings. It will parse the string, check a few values to ensure the AST is correct, and then call your `free_json()` function. If ASAN detects any memory leaks upon program exit, you fail.

When you are done, compile the code using `gcc -O2 -Wall -Werror -fsanitize=address -o /out/json_bench target.c` and ensure it runs successfully. If it prints "FLAG: JSON ASAN Success!", you have passed.
