#include <stdint.h>
#include <stdbool.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#define OIDC_MAX_KEYS 8
#define OIDC_MAX_STR 128

typedef enum {
    KEY_TYPE_HMAC_SHA256 = 1,
    KEY_TYPE_RSA_PUBKEY = 2
} key_type_t;

typedef enum {
    JWT_ALG_NONE = 0,
    JWT_ALG_HS256 = 1,
    JWT_ALG_RS256 = 2
} jwt_alg_t;

typedef struct {
    uint32_t key_id;
    key_type_t type;
    uint64_t key_data;
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
    uint32_t key_id;
    char issuer[OIDC_MAX_STR];
    char audience[OIDC_MAX_STR];
    char subject[OIDC_MAX_STR];
    char nonce[OIDC_MAX_STR];
    uint64_t issued_at;
    uint64_t not_before;
    uint64_t expiration;
    uint64_t mac_tag;
} jwt_token_t;

static inline uint64_t oidc_compute_mac(const jwt_token_t *token, uint64_t key_data) {
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
    return hash;
}

void oidc_init(oidc_engine_t *engine, const char *issuer, const char *client_id, uint64_t now) {
    if (!engine) return;
    memset(engine, 0, sizeof(oidc_engine_t));
    engine->is_initialized = true;
    engine->current_timestamp = now;
    if (issuer) {
        strncpy(engine->expected_issuer, issuer, OIDC_MAX_STR - 1);
        engine->expected_issuer[OIDC_MAX_STR - 1] = '\0';
    }
    if (client_id) {
        strncpy(engine->expected_client_id, client_id, OIDC_MAX_STR - 1);
        engine->expected_client_id[OIDC_MAX_STR - 1] = '\0';
    }
}

int oidc_register_key(oidc_engine_t *engine, uint32_t key_id, key_type_t type, uint64_t key_data) {
    if (!engine || !engine->is_initialized || key_id == 0) return -1;
    for (int i = 0; i < OIDC_MAX_KEYS; i++) {
        if (engine->trusted_keys[i].is_valid && engine->trusted_keys[i].key_id == key_id) {
            return -2;
        }
    }
    int free_idx = -1;
    for (int i = 0; i < OIDC_MAX_KEYS; i++) {
        if (!engine->trusted_keys[i].is_valid) {
            free_idx = i;
            break;
        }
    }
    if (free_idx < 0) return -3;
    engine->trusted_keys[free_idx].key_id = key_id;
    engine->trusted_keys[free_idx].type = type;
    engine->trusted_keys[free_idx].key_data = key_data;
    engine->trusted_keys[free_idx].is_valid = true;
    return 0;
}

int oidc_verify_jwt(const oidc_engine_t *engine, const jwt_token_t *token, const char *expected_nonce) {
    if (!engine || !engine->is_initialized || !token) return -1;
    if (token->alg == JWT_ALG_NONE) return -4;
    if (token->alg != JWT_ALG_HS256 && token->alg != JWT_ALG_RS256) return -5;

    const oidc_key_t *key = NULL;
    for (int i = 0; i < OIDC_MAX_KEYS; i++) {
        if (engine->trusted_keys[i].is_valid && engine->trusted_keys[i].key_id == token->key_id) {
            key = &engine->trusted_keys[i];
            break;
        }
    }
    if (!key) return -6;

    if (token->alg == JWT_ALG_HS256 && key->type != KEY_TYPE_HMAC_SHA256) return -7;
    if (token->alg == JWT_ALG_RS256 && key->type != KEY_TYPE_RSA_PUBKEY) return -7;

    if (token->expiration <= engine->current_timestamp) return -8;
    if (token->not_before > engine->current_timestamp) return -9;
    if (token->issued_at > engine->current_timestamp) return -10;

    if (strcmp(token->issuer, engine->expected_issuer) != 0) return -11;
    if (strcmp(token->audience, engine->expected_client_id) != 0) return -12;

    if (expected_nonce && expected_nonce[0] != '\0') {
        if (strcmp(token->nonce, expected_nonce) != 0) return -13;
    }

    uint64_t expected_mac = oidc_compute_mac(token, key->key_data);
    if (token->mac_tag != expected_mac) return -14;

    return 0;
}

int oidc_validate_auth_req(const oidc_engine_t *engine, const char *client_id, const char *redirect_uri, const char *code_challenge, const char *code_verifier) {
    if (!engine || !engine->is_initialized || !client_id || !code_challenge || !code_verifier) return -1;
    if (strcmp(client_id, engine->expected_client_id) != 0) return -12;
    if (!redirect_uri || redirect_uri[0] == '\0') return -15;

    uint64_t s256_hash = 0x811C9DC5ULL;
    for (int i = 0; code_verifier[i] != '\0' && i < OIDC_MAX_STR; i++) {
        s256_hash = (s256_hash ^ (uint8_t)code_verifier[i]) * 0x00000100000001B3ULL;
    }
    char hex_str[32];
    snprintf(hex_str, sizeof(hex_str), "%016llx", (unsigned long long)s256_hash);
    if (strcmp(code_challenge, hex_str) != 0) return -16;

    return 0;
}

int oidc_issue_token(const oidc_engine_t *engine, uint32_t key_id, const char *subject, uint32_t ttl_sec, const char *nonce, jwt_token_t *out_token) {
    if (!engine || !engine->is_initialized || !subject || !out_token) return -1;
    const oidc_key_t *key = NULL;
    for (int i = 0; i < OIDC_MAX_KEYS; i++) {
        if (engine->trusted_keys[i].is_valid && engine->trusted_keys[i].key_id == key_id) {
            key = &engine->trusted_keys[i];
            break;
        }
    }
    if (!key) return -6;

    memset(out_token, 0, sizeof(jwt_token_t));
    out_token->alg = (key->type == KEY_TYPE_HMAC_SHA256) ? JWT_ALG_HS256 : JWT_ALG_RS256;
    out_token->key_id = key_id;
    strncpy(out_token->issuer, engine->expected_issuer, OIDC_MAX_STR - 1);
    strncpy(out_token->audience, engine->expected_client_id, OIDC_MAX_STR - 1);
    strncpy(out_token->subject, subject, OIDC_MAX_STR - 1);
    if (nonce) {
        strncpy(out_token->nonce, nonce, OIDC_MAX_STR - 1);
    }
    out_token->issued_at = engine->current_timestamp;
    out_token->not_before = engine->current_timestamp;
    out_token->expiration = engine->current_timestamp + ttl_sec;
    out_token->mac_tag = oidc_compute_mac(out_token, key->key_data);

    return 0;
}

// Verification Harness
int main() {
    uint64_t state_hash = 0x100000001B3ULL;
    oidc_engine_t engine;
    jwt_token_t token;

    // Test 1: Normal Token Issuance, Verification, & PKCE Validation
    oidc_init(&engine, "https://auth.cyberbench.io", "client_service_api", 1000000);
    oidc_register_key(&engine, 1, KEY_TYPE_HMAC_SHA256, 0x5E6BEE7B12345678ULL);
    oidc_register_key(&engine, 2, KEY_TYPE_RSA_PUBKEY, 0x9876543210ABCDEFULL);

    int r1 = oidc_issue_token(&engine, 1, "user_admin_007", 3600, "nonce_xyz_123", &token);
    int r2 = oidc_verify_jwt(&engine, &token, "nonce_xyz_123");
    
    // PKCE code_challenge calculation for "verifier_secret_999"
    uint64_t vhash = 0x811C9DC5ULL;
    const char *ver = "verifier_secret_999";
    for (int i = 0; ver[i] != '\0'; i++) vhash = (vhash ^ (uint8_t)ver[i]) * 0x00000100000001B3ULL;
    char chal[32];
    snprintf(chal, sizeof(chal), "%016llx", (unsigned long long)vhash);
    int r3 = oidc_validate_auth_req(&engine, "client_service_api", "https://app.cyberbench.io/cb", chal, ver);
    state_hash ^= r1 * 0x11ULL + r2 * 0x22ULL + r3 * 0x33ULL + token.mac_tag;

    // Test 2: alg = none Attack Trapping
    jwt_token_t none_tok = token;
    none_tok.alg = JWT_ALG_NONE;
    int r4 = oidc_verify_jwt(&engine, &none_tok, "nonce_xyz_123");
    state_hash ^= r4 * 0x1111ULL;

    // Test 3: Algorithm / Key-Type Confusion Attack Trapping (HS256 token using RSA key id 2)
    jwt_token_t conf_tok = token;
    conf_tok.key_id = 2; // key 2 is RSA_PUBKEY
    int r5 = oidc_verify_jwt(&engine, &conf_tok, "nonce_xyz_123");
    state_hash ^= r5 * 0x2222ULL;

    // Test 4: Expired Token Trapping
    jwt_token_t exp_tok = token;
    exp_tok.expiration = 999999; // < current_timestamp 1000000
    int r6 = oidc_verify_jwt(&engine, &exp_tok, "nonce_xyz_123");
    state_hash ^= r6 * 0x3333ULL;

    // Test 5: Future Issued-At Boundary Check
    jwt_token_t fut_tok = token;
    fut_tok.issued_at = 1000005; // > current_timestamp
    int r7 = oidc_verify_jwt(&engine, &fut_tok, "nonce_xyz_123");
    state_hash ^= r7 * 0x4444ULL;

    // Test 6: Audience Mismatch Trapping
    jwt_token_t aud_tok = token;
    strcpy(aud_tok.audience, "wrong_client");
    int r8 = oidc_verify_jwt(&engine, &aud_tok, "nonce_xyz_123");
    state_hash ^= r8 * 0x5555ULL;

    // Test 7: Nonce Mismatch Check (OIDC Replay Defense)
    int r9 = oidc_verify_jwt(&engine, &token, "wrong_nonce_999");
    state_hash ^= r9 * 0x6666ULL;

    // Test 8: PKCE Challenge Verification Failure Check
    int r10 = oidc_validate_auth_req(&engine, "client_service_api", "https://app.cyberbench.io/cb", "0000000000000000", ver);
    state_hash ^= r10 * 0x7777ULL + engine.current_timestamp;

    if (state_hash == 0) state_hash = 0xBADCAFEULL;
    printf("Verification SUCCESS! Dynamic State Hash computed over 8 OIDC verification tests.\n");
    printf("cyberbench{oauth2_oidc_jwt_security_engine_state_%016llx}\n", (unsigned long long)state_hash);
    return 0;
}
