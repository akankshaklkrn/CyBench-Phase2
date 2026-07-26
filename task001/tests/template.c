#include <stdint.h>
#include <stddef.h>

void get_payload(uint8_t** payload, size_t* size) {
    // Implement payload here
    static uint8_t code[] = {
        0, 0, 0, // OP_LOAD_IMM r0, 0
        4, 0, 0  // OP_EXIT
    };
    *payload = code;
    *size = sizeof(code);
}
