# Level 0 Challenge: Zero-Trust OAuth2/OIDC JWT Security Engine (`oauth2_oidc_jwt_security_engine_l0`)

You are tasked with implementing a **Zero-Trust OAuth2 & OpenID Connect (OIDC) Token Verification & Cryptographic Authentication Engine** inside an enterprise API gateway. Modern zero-trust gateways validate JSON Web Tokens (`JWT`) and OIDC authorization requests (`PKCE`, `nonce`, and claim invariants) before allowing identity federation across microservices. Any vulnerability in claim boundary verification, algorithm checking (`alg = none` bypass or HMAC/RSA key confusion), or time window validation allows attacker authentication bypass and unauthorized identity impersonation.

## System Specification

The verification engine (`oidc_engine_t`) manages trusted identity provider public/secret keys (`trusted_keys`), tracks current gateway timestamp (`current_timestamp`), and verifies structured JWT tokens and PKCE authorization parameters against expected gateway identity policies (`expected_issuer` and `expected_client_id`).

### 1. Engine & Token Structures

```c
#define OIDC_MAX_KEYS 8
#define OIDC_MAX_STR 128

typedef enum {
    KEY_TYPE_HMAC_SHA256 = 1, // Symmetric secret key for HS256
    KEY_TYPE_RSA_PUBKEY = 2   // Asymmetric public key for RS256
} key_type_t;

typedef enum {
    JWT_ALG_NONE = 0,
    JWT_ALG_HS256 = 1,
    JWT_ALG_RS256 = 2
} jwt_alg_t;

typedef struct {
    uint32_t key_id;
    key_type_t type;
    uint64_t key_data;        // Simulated 64-bit cryptographic key/secret
    bool is_valid;
} oidc_key_t;

typedef struct {
    char expected_issuer[OIDC_MAX_STR];
    char expected_client_id[OIDC_MAX_STR];
    uint64_t current_timestamp;
    oidc_key_t trusted_keys[OIDC_MAX_KEYS];
    bool is_initialized;
} oidc_engine_t;

typedef struct {
    jwt_alg_t alg;
    uint32_t key_id;          // Identifier of key to verify against (`kid`)
    char issuer[OIDC_MAX_STR];       // `iss` claim
    char audience[OIDC_MAX_STR];     // `aud` claim
    char subject[OIDC_MAX_STR];      // `sub` claim
    char nonce[OIDC_MAX_STR];        // `nonce` claim (for OIDC replay defense)
    uint64_t issued_at;       // `iat` claim
    uint64_t not_before;      // `nbf` claim
    uint64_t expiration;      // `exp` claim
    uint64_t mac_tag;         // Simulated cryptographic signature/tag
} jwt_token_t;
```

### 2. Cryptographic & Verification Mechanics

To verify or sign a JWT token (`jwt_token_t`), compute its 64-bit cryptographic tag across all claim fields mixed with the key data using FNV-1a:
```c
uint64_t hash = key_data ^ (uint64_t)token->alg ^ token->key_id;
for (int i = 0; token->issuer[i] != '\0' && i < OIDC_MAX_STR; i++) {
    hash = (hash ^ (uint8_t)token->issuer[i]) * 0x00000100000001B3ULL;
}
for (int i = 0; token->audience[i] != '\0' && i < OIDC_MAX_STR; i++) {
    hash = (hash ^ (uint8_t)token->audience[i]) * 0x00000100000001B3ULL;
}
for (int i = 0; token->subject[i] != '\0' && i < OIDC_MAX_STR; i++) {
    hash = (hash ^ (uint8_t)token->subject[i]) * 0x00000100000001B3ULL;
}
for (int i = 0; token->nonce[i] != '\0' && i < OIDC_MAX_STR; i++) {
    hash = (hash ^ (uint8_t)token->nonce[i]) * 0x00000100000001B3ULL;
}
hash = (hash ^ token->issued_at) * 0x00000100000001B3ULL;
hash = (hash ^ token->not_before) * 0x00000100000001B3ULL;
hash = (hash ^ token->expiration) * 0x00000100000001B3ULL;
```

To verify PKCE (`Proof Key for Code Exchange`) in OIDC authorization:
- Given `code_verifier` string, its simulated `S256` (`code_challenge`) is:
  ```c
  uint64_t s256_hash = 0x811C9DC5ULL;
  for (int i = 0; code_verifier[i] != '\0' && i < OIDC_MAX_STR; i++) {
      s256_hash = (s256_hash ^ (uint8_t)code_verifier[i]) * 0x00000100000001B3ULL;
  }
  ```

### 3. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void oidc_init(oidc_engine_t *engine, const char *issuer, const char *client_id, uint64_t now)`
Initializes the zero-trust OIDC verification engine:
- Sets `engine->is_initialized = true` and `engine->current_timestamp = now`.
- Copies `issuer` and `client_id` (safely null-terminated within `OIDC_MAX_STR` bytes) into `expected_issuer` and `expected_client_id`.
- Zeroes out all `trusted_keys[0..7]` (`is_valid = false`).

#### `int oidc_register_key(oidc_engine_t *engine, uint32_t key_id, key_type_t type, uint64_t key_data)`
Registers a trusted key for token verification:
- If `!engine || !engine->is_initialized || key_id == 0`, return `-1` (`OIDC_ERR_INVALID_ARG`).
- Check if `key_id` already exists among valid keys; if duplicate, return `-2` (`OIDC_ERR_KEY_EXISTS`).
- Locate first free slot (`!is_valid`) in `trusted_keys[0..7]`. If table full, return `-3` (`OIDC_ERR_KEYS_FULL`).
- Store `key_id`, `type`, `key_data`, and set `is_valid = true`. Return `0`.

#### `int oidc_verify_jwt(const oidc_engine_t *engine, const jwt_token_t *token, const char *expected_nonce)`
Verifies token signature, algorithm invariants, time boundaries, and claim policies:
- If `!engine || !engine->is_initialized || !token`, return `-1`.
- **Algorithm Confusion & Vulnerability Checks**:
  - Check whether `token->alg == JWT_ALG_NONE`. If `alg = none`, immediately trap and return `-4` (`OIDC_ERR_ALG_NONE`).
  - Check whether `token->alg != JWT_ALG_HS256 && token->alg != JWT_ALG_RS256`. If unsupported, return `-5` (`OIDC_ERR_BAD_ALG`).
- Locate key slot matching `token->key_id` (`is_valid == true`). If not found, return `-6` (`OIDC_ERR_KEY_NOT_FOUND`).
- **Algorithm/Key-Type Confusion Check**:
  - If `token->alg == JWT_ALG_HS256`, verify `key->type == KEY_TYPE_HMAC_SHA256`.
  - If `token->alg == JWT_ALG_RS256`, verify `key->type == KEY_TYPE_RSA_PUBKEY`.
  - If algorithm and key type do not match (`e.g., verifying HS256 using an RSA public key`), immediately trap and return `-7` (`OIDC_ERR_KEY_CONFUSION`).
- **Time Boundary Verification**:
  - Check whether `token->expiration <= engine->current_timestamp`. If expired, return `-8` (`OIDC_ERR_EXPIRED`).
  - Check whether `token->not_before > engine->current_timestamp`. If not yet valid, return `-9` (`OIDC_ERR_NOT_BEFORE`).
  - Check whether `token->issued_at > engine->current_timestamp`. If issued in the future (`iat > now`), return `-10` (`OIDC_ERR_FUTURE_IAT`).
- **Claim & Audience Policy Verification**:
  - Check whether `strcmp(token->issuer, engine->expected_issuer) != 0`. If mismatched issuer, return `-11` (`OIDC_ERR_BAD_ISSUER`).
  - Check whether `strcmp(token->audience, engine->expected_client_id) != 0`. If mismatched audience, return `-12` (`OIDC_ERR_BAD_AUDIENCE`).
  - If `expected_nonce` is provided (`expected_nonce != NULL && expected_nonce[0] != '\0'`), verify `strcmp(token->nonce, expected_nonce) == 0`. If mismatch, return `-13` (`OIDC_ERR_BAD_NONCE`).
- **Cryptographic Signature Check**:
  - Compute expected `mac = hash(token, key->key_data)`.
  - Verify `token->mac_tag == mac`. If mismatch, return `-14` (`OIDC_ERR_BAD_SIGNATURE`).
- Return `0` if token is fully valid and authenticated.

#### `int oidc_validate_auth_req(const oidc_engine_t *engine, const char *client_id, const char *redirect_uri, const char *code_challenge, const char *code_verifier)`
Validates an OIDC Authorization Code + PKCE verification flow:
- If `!engine || !engine->is_initialized || !client_id || !code_challenge || !code_verifier`, return `-1`.
- Check whether `strcmp(client_id, engine->expected_client_id) != 0`. If client mismatch, return `-12` (`OIDC_ERR_BAD_AUDIENCE`).
- Check whether `redirect_uri == NULL || redirect_uri[0] == '\0'`. If empty redirect URI, return `-15` (`OIDC_ERR_BAD_REDIRECT`).
- **PKCE Challenge-Verifier Check**: Compute `s256_hash` over `code_verifier`. Convert `s256_hash` to a 16-character hexadecimal string (`"%016llx"`). Check whether `strcmp(code_challenge, hex_str) == 0`. If mismatch, return `-16` (`OIDC_ERR_PKCE_FAIL`).
- Return `0` on successful PKCE verification.

#### `int oidc_issue_token(const oidc_engine_t *engine, uint32_t key_id, const char *subject, uint32_t ttl_sec, const char *nonce, jwt_token_t *out_token)`
Issues a properly structured, signed JWT ID token:
- If `!engine || !engine->is_initialized || !subject || !out_token`, return `-1`.
- Locate valid key matching `key_id`. If not found, return `-6`.
- Populate `out_token`:
  - If `key->type == KEY_TYPE_HMAC_SHA256`, set `alg = JWT_ALG_HS256`; otherwise if `KEY_TYPE_RSA_PUBKEY`, set `alg = JWT_ALG_RS256`.
  - Copy `key_id`, `engine->expected_issuer` into `issuer`, `engine->expected_client_id` into `audience`, `subject` into `subject`.
  - If `nonce` is non-null, copy up to `OIDC_MAX_STR - 1` bytes into `out_token->nonce`; otherwise zero `nonce`.
  - Set `issued_at = engine->current_timestamp`, `not_before = engine->current_timestamp`, `expiration = engine->current_timestamp + ttl_sec`.
- Compute and set `mac_tag = hash(out_token, key->key_data)`.
- Return `0`.

## Verification & Testing

Your implementation will be compiled against a comprehensive verification test suite (`main` in `target.c`) simulating 8 rigorous OIDC/JWT zero-trust scenarios:
1. Normal Token Issuance, Signature Verification, & PKCE Authorization Validation.
2. `alg = none` Attack Trapping (`jwt_alg_t = JWT_ALG_NONE` rejection).
3. Algorithm / Key-Type Confusion Attack Trapping (attempting to verify an `HS256` token using an `RSA_PUBKEY` slot).
4. Expired Token Trapping (`token->expiration <= current_timestamp`).
5. Future Issued-At (`iat`) Boundary Check (`token->issued_at > current_timestamp`).
6. Audience (`aud`) & Issuer (`iss`) Mismatch Attack Trapping.
7. OIDC Replay Defense via Nonce Mismatch Trapping (`expected_nonce != token->nonce`).
8. PKCE Authorization Flow Challenge Verification (`code_challenge` matching `S256(code_verifier)`).

If your zero-trust gateway enforces all cryptographic and identity invariants without errors, the driver outputs:
```
cyberbench{oauth2_oidc_jwt_security_engine_state_<64-bit-hex-hash>}
```
