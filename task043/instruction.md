# Level 0 Challenge: Strict TLS 1.3 Handshake & Cryptographic Record Engine (`tls_handshake_state_machine_l0`)

You are tasked with implementing a **Strict TLS 1.3 Cryptographic Handshake State Machine & Record Layer Protection Engine** inside a high-security C implementation. Network protocols in secure infrastructure must enforce rigorous ordering invariants, exact cryptographic secret expansion using HKDF-like primitives, anti-replay protections via strictly monotonic record sequence numbers, and authentication tag verification. Any deviation or state transition anomaly allows protocol downgrade attacks, record injection, or key compromise.

## System Specification

The core engine is structured around `tls_ctx_t`, which tracks the exact state of a TLS session between a client and a server (`is_client`).

### 1. Cryptographic & State Structures

```c
typedef enum {
    TLS_STATE_START = 0,
    TLS_STATE_WAIT_SH = 1,
    TLS_STATE_WAIT_EE = 2,
    TLS_STATE_WAIT_FIN = 3,
    TLS_STATE_CONNECTED = 4,
    TLS_STATE_ERROR = 5
} tls_state_t;

typedef enum {
    TLS_MSG_CLIENT_HELLO = 1,
    TLS_MSG_SERVER_HELLO = 2,
    TLS_MSG_ENCRYPTED_EXTENSIONS = 3,
    TLS_MSG_FINISHED = 4,
    TLS_MSG_APP_DATA = 23
} tls_msg_type_t;

typedef struct {
    tls_msg_type_t type;
    uint32_t seq_num;
    uint32_t payload_len;
    uint8_t payload[64];
    uint32_t auth_tag;
} tls_record_t;

typedef struct {
    bool is_client;
    tls_state_t state;
    uint32_t read_seq;
    uint32_t write_seq;
    uint32_t handshake_secret;
    uint32_t traffic_secret;
    uint32_t transcript_hash;
    bool keys_derived;
} tls_ctx_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void tls_init(tls_ctx_t *ctx, bool is_client)`
Initializes the TLS session context:
- Sets `is_client` field.
- Sets `state` to `TLS_STATE_START`.
- Initializes `read_seq = 0`, `write_seq = 0`, `handshake_secret = 0`, `traffic_secret = 0`, `transcript_hash = 0x811C9DC5` (FNV-1a offset basis).
- Sets `keys_derived = false`.

#### `void tls_update_transcript(tls_ctx_t *ctx, const tls_record_t *rec)`
Updates the running transcript hash (`transcript_hash`) across handshake records using FNV-1a 32-bit:
- For each byte in `rec->payload` up to `rec->payload_len` (must cap at `64`):
  `transcript_hash = (transcript_hash ^ byte) * 0x01000193;`
- Also mix in `rec->type` (as a single `uint8_t` byte):
  `transcript_hash = (transcript_hash ^ rec->type) * 0x01000193;`

#### `int tls_derive_keys(tls_ctx_t *ctx, uint32_t shared_secret)`
Simulates HKDF key extraction and expansion to derive session secrets:
- Must only succeed (`return 0`) if `ctx->state == TLS_STATE_WAIT_EE` (for client when processing `ServerHello` transition) or `ctx->state == TLS_STATE_START` (when server initializes with shared secret). Otherwise, transition state to `TLS_STATE_ERROR` and return `-1`.
- Compute:
  `ctx->handshake_secret = (shared_secret ^ ctx->transcript_hash) + 0x9e3779b9;`
  `ctx->traffic_secret = (ctx->handshake_secret * 0x01000193) ^ 0x3c6ef372;`
- Mark `ctx->keys_derived = true;` and return `0`.

#### `uint32_t tls_compute_mac(tls_ctx_t *ctx, const tls_record_t *rec)`
Computes the expected 32-bit authentication tag (`auth_tag`) for a record:
- If `!ctx->keys_derived`, return `0` (unencrypted plaintext handshake records prior to key derivation).
- Otherwise, compute MAC over `rec->type`, `rec->seq_num`, `rec->payload_len`, and payload bytes using the current `traffic_secret`:
  ```c
  uint32_t mac = ctx->traffic_secret ^ rec->type ^ (rec->seq_num * 0x9e3779b9);
  for (uint32_t i = 0; i < rec->payload_len && i < 64; i++) {
      mac = (mac ^ rec->payload[i]) * 0x01000193;
  }
  return mac;
  ```

#### `int tls_process_record(tls_ctx_t *ctx, const tls_record_t *rec, uint8_t *out_data, uint32_t *out_len)`
Processes an incoming TLS record and advances the strict state machine:
1. **Sequence Number Enforcement**:
   - `rec->seq_num` MUST exactly equal `ctx->read_seq`. If `rec->seq_num != ctx->read_seq`, or if `rec->payload_len > 64`, immediately transition `ctx->state = TLS_STATE_ERROR` and return `-1` (`TLS_ERR_PROTOCOL`).
2. **MAC Verification (if `ctx->keys_derived`)**:
   - Compute `expected_mac = tls_compute_mac(ctx, rec)`.
   - If `rec->auth_tag != expected_mac`, immediately transition `ctx->state = TLS_STATE_ERROR` and return `-2` (`TLS_ERR_AUTH_FAILED`).
3. **Strict State Transitions & Processing (`ctx->is_client == true`)**:
   - **If `ctx->state == TLS_STATE_START`**:
     - Must receive `TLS_MSG_SERVER_HELLO`. Any other message -> `TLS_STATE_ERROR`, return `-1`.
     - Update transcript via `tls_update_transcript(ctx, rec)`.
     - Extract `shared_secret` from `rec->payload[0..3]` (as little-endian/host `uint32_t` or `*(uint32_t*)rec->payload`).
     - Set `ctx->state = TLS_STATE_WAIT_EE`.
     - Call `tls_derive_keys(ctx, *(uint32_t*)rec->payload)`.
     - Increment `ctx->read_seq++` and return `0`.
   - **If `ctx->state == TLS_STATE_WAIT_EE`**:
     - Must receive `TLS_MSG_ENCRYPTED_EXTENSIONS`. Any other message -> `TLS_STATE_ERROR`, return `-1`.
     - Update transcript via `tls_update_transcript(ctx, rec)`.
     - Set `ctx->state = TLS_STATE_WAIT_FIN`.
     - Increment `ctx->read_seq++` and return `0`.
   - **If `ctx->state == TLS_STATE_WAIT_FIN`**:
     - Must receive `TLS_MSG_FINISHED`. Any other message -> `TLS_STATE_ERROR`, return `-1`.
     - Verify that `rec->payload_len >= 4` and `*(uint32_t*)rec->payload == (ctx->handshake_secret ^ ctx->transcript_hash)`. If mismatch -> `TLS_STATE_ERROR`, return `-2`.
     - Update transcript via `tls_update_transcript(ctx, rec)`.
     - Set `ctx->state = TLS_STATE_CONNECTED`.
     - Increment `ctx->read_seq++` and return `0`.
   - **If `ctx->state == TLS_STATE_CONNECTED`**:
     - Must receive `TLS_MSG_APP_DATA`. Any other message -> `TLS_STATE_ERROR`, return `-1`.
     - Copy `rec->payload` to `out_data` (up to `rec->payload_len`) and set `*out_len = rec->payload_len`.
     - Increment `ctx->read_seq++` and return `0`.
   - **If `ctx->state == TLS_STATE_ERROR`**:
     - Return `-1`.

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) that simulates 8 rigorous security scenarios:
1. Normal TLS 1.3 Client Handshake & Application Data Exchange
2. Out-of-Order Handshake Message Rejection (`Finished` before `EncryptedExtensions`)
3. Sequence Number Replay Attack Trapping (`seq_num` reuse)
4. Cryptographic Authentication Tag (`auth_tag`) Tampering & MAC Verification Failure
5. Invalid Shared Secret Key Derivation & Handshake Secret Verification
6. Premature Application Data Injection during Handshake (`TLS_STATE_WAIT_EE`)
7. Transcript Hash Continuity & FNV-1a Mixing Integrity
8. Multi-Record Application Data Stream Sequence Increment & Decryption

If your state machine logic accurately satisfies all cryptographic and ordering constraints without memory anomalies, the verification driver will output the cryptographic dynamic state hash:
```
cyberbench{tls_handshake_state_machine_state_<64-bit-hex-hash>}
```
