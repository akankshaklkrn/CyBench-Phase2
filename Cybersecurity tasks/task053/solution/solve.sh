#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#define SAML_MAX_STR_LEN      256
#define SAML_MAX_XML_BYTES    2048
#define SAML_DIGEST_LEN       32
#define SAML_MAX_ASSERTIONS   16

typedef enum {
    CANON_EXCL_C14N = 1, /* Exclusive Canonicalization without comments */
    CANON_INCL_C14N = 2
} xmldsig_canon_t;

typedef struct {
    char            ref_uri[SAML_MAX_STR_LEN]; /* e.g. "#_assertion_id_1" */
    uint8_t         digest_val[SAML_DIGEST_LEN];
    xmldsig_canon_t canon_method;
} xmldsig_ref_t;

typedef struct {
    xmldsig_ref_t   reference;
    uint8_t         signature_val[32];
    char            signer_cert_id[SAML_MAX_STR_LEN];
    bool            is_present;
} xmldsig_sig_t;

typedef struct {
    char          assertion_id[SAML_MAX_STR_LEN];
    char          issuer[SAML_MAX_STR_LEN];
    char          subject[SAML_MAX_STR_LEN];
    char          audience[SAML_MAX_STR_LEN];
    uint64_t      not_before;
    uint64_t      not_on_or_after;
    xmldsig_sig_t signature;
    bool          is_valid;
} saml_assertion_t;

typedef struct {
    saml_assertion_t assertions[SAML_MAX_ASSERTIONS];
    uint32_t         assertion_count;
    char             expected_audience[SAML_MAX_STR_LEN];
    char             trusted_issuer[SAML_MAX_STR_LEN];
    uint64_t         current_time;
    bool             is_initialized;
} saml_engine_t;

/* Error codes */
#define SAML_ERR_INVALID_ARG       -1
#define SAML_ERR_XXE_INJECTION     -2 /* <!DOCTYPE, <!ENTITY, or SYSTEM reference detected in XML */
#define SAML_ERR_XSW_ATTACK        -3 /* XML Signature Wrapping attack / Reference URI ID mismatch / Duplicate IDs */
#define SAML_ERR_DIGEST_MISMATCH   -4 /* SHA-256 canonical digest verification failure */
#define SAML_ERR_AUDIENCE_MISMATCH -5
#define SAML_ERR_EXPIRED           -6 /* Temporal window check failure (not_before / not_on_or_after) */
#define SAML_ERR_ISSUER_UNTRUSTED  -7
#define SAML_ERR_UNSIGNED          -8

void saml_init_engine(saml_engine_t *engine, const char *trusted_issuer, const char *expected_audience, uint64_t current_time) {
    if (!engine || !trusted_issuer || !expected_audience) return;
    memset(engine, 0, sizeof(saml_engine_t));
    strncpy(engine->trusted_issuer, trusted_issuer, SAML_MAX_STR_LEN - 1);
    strncpy(engine->expected_audience, expected_audience, SAML_MAX_STR_LEN - 1);
    engine->current_time = current_time;
    engine->is_initialized = true;
}

int saml_check_xxe_injection(const char *raw_xml) {
    if (!raw_xml) return SAML_ERR_INVALID_ARG;
    if (strstr(raw_xml, "<!DOCTYPE") || strstr(raw_xml, "<!ENTITY") || strstr(raw_xml, "SYSTEM")) {
        return SAML_ERR_XXE_INJECTION;
    }
    return 0;
}

int saml_verify_xmldsig_digest(const xmldsig_ref_t *ref, const char *assertion_id, const uint8_t *computed_digest) {
    if (!ref || !assertion_id || !computed_digest) return SAML_ERR_INVALID_ARG;
    if (ref->ref_uri[0] != '#' || strcmp(ref->ref_uri + 1, assertion_id) != 0) {
        return SAML_ERR_XSW_ATTACK;
    }
    if (ref->canon_method != CANON_EXCL_C14N) {
        return SAML_ERR_DIGEST_MISMATCH;
    }
    if (memcmp(ref->digest_val, computed_digest, SAML_DIGEST_LEN) != 0) {
        return SAML_ERR_DIGEST_MISMATCH;
    }
    return 0;
}

int saml_add_assertion(saml_engine_t *engine, const saml_assertion_t *assertion, const char *raw_xml) {
    if (!engine || !engine->is_initialized || !assertion) return SAML_ERR_INVALID_ARG;
    int xxe_check = saml_check_xxe_injection(raw_xml);
    if (xxe_check != 0) return xxe_check;
    if (engine->assertion_count >= SAML_MAX_ASSERTIONS) return SAML_ERR_INVALID_ARG;
    for (uint32_t i = 0; i < engine->assertion_count; i++) {
        if (strcmp(engine->assertions[i].assertion_id, assertion->assertion_id) == 0) {
            return SAML_ERR_XSW_ATTACK;
        }
    }
    engine->assertions[engine->assertion_count++] = *assertion;
    return 0;
}

int saml_verify_assertion_sso(saml_engine_t *engine, uint32_t assertion_index, const uint8_t *computed_digest) {
    if (!engine || !engine->is_initialized || !computed_digest || assertion_index >= engine->assertion_count) {
        return SAML_ERR_INVALID_ARG;
    }
    saml_assertion_t *a = &engine->assertions[assertion_index];
    if (!a->signature.is_present) {
        return SAML_ERR_UNSIGNED;
    }
    int dsig_check = saml_verify_xmldsig_digest(&a->signature.reference, a->assertion_id, computed_digest);
    if (dsig_check != 0) return dsig_check;
    if (strcmp(a->issuer, engine->trusted_issuer) != 0) {
        return SAML_ERR_ISSUER_UNTRUSTED;
    }
    if (strcmp(a->audience, engine->expected_audience) != 0) {
        return SAML_ERR_AUDIENCE_MISMATCH;
    }
    if (engine->current_time < a->not_before || engine->current_time > a->not_on_or_after) {
        return SAML_ERR_EXPIRED;
    }
    a->is_valid = true;
    return 0;
}

/* Verification test suite in main() */
int main(void) {
    saml_engine_t engine;
    saml_init_engine(&engine, "https://idp.enterprise.com", "https://app.enterprise.com", 1700000000ULL);

    uint8_t valid_digest[32];
    memset(valid_digest, 0xAA, sizeof(valid_digest));

    saml_assertion_t valid_assertion;
    memset(&valid_assertion, 0, sizeof(valid_assertion));
    strcpy(valid_assertion.assertion_id, "_assertion_12345");
    strcpy(valid_assertion.issuer, "https://idp.enterprise.com");
    strcpy(valid_assertion.subject, "user@enterprise.com");
    strcpy(valid_assertion.audience, "https://app.enterprise.com");
    valid_assertion.not_before = 1699999000ULL;
    valid_assertion.not_on_or_after = 1700001000ULL;
    valid_assertion.signature.is_present = true;
    valid_assertion.signature.reference.canon_method = CANON_EXCL_C14N;
    strcpy(valid_assertion.signature.reference.ref_uri, "#_assertion_12345");
    memcpy(valid_assertion.signature.reference.digest_val, valid_digest, sizeof(valid_digest));

    int passed = 0;
    int total = 8;

    /* Test 1: Normal valid SAML SSO and XMLDSig check */
    if (saml_add_assertion(&engine, &valid_assertion, "<Assertion ID=\"_assertion_12345\"></Assertion>") == 0 &&
        saml_verify_assertion_sso(&engine, 0, valid_digest) == 0 && engine.assertions[0].is_valid) {
        passed++;
    }

    /* Test 2: XXE / DTD injection trapping */
    if (saml_add_assertion(&engine, &valid_assertion, "<!DOCTYPE foo SYSTEM \"file:///etc/passwd\">") == SAML_ERR_XXE_INJECTION) {
        passed++;
    }

    /* Test 3: XML Signature Wrapping (XSW) URI mismatch trapping */
    saml_assertion_t bad_xsw = valid_assertion;
    strcpy(bad_xsw.assertion_id, "_assertion_admin");
    strcpy(bad_xsw.signature.reference.ref_uri, "#_assertion_user");
    saml_add_assertion(&engine, &bad_xsw, "<Assertion ID=\"_assertion_admin\"></Assertion>");
    if (saml_verify_assertion_sso(&engine, engine.assertion_count - 1, valid_digest) == SAML_ERR_XSW_ATTACK) {
        passed++;
    }

    /* Test 4: XML Signature Wrapping duplicate ID check */
    if (saml_add_assertion(&engine, &valid_assertion, "<Assertion ID=\"_assertion_12345\"></Assertion>") == SAML_ERR_XSW_ATTACK) {
        passed++;
    }

    /* Test 5: Canonical digest mismatch check */
    uint8_t bad_digest[32];
    memset(bad_digest, 0xBB, sizeof(bad_digest));
    if (saml_verify_assertion_sso(&engine, 0, bad_digest) == SAML_ERR_DIGEST_MISMATCH) {
        passed++;
    }

    /* Test 6: Untrusted issuer check */
    saml_assertion_t bad_issuer = valid_assertion;
    strcpy(bad_issuer.assertion_id, "_assertion_issuer");
    strcpy(bad_issuer.issuer, "https://evil.idp.com");
    strcpy(bad_issuer.signature.reference.ref_uri, "#_assertion_issuer");
    saml_add_assertion(&engine, &bad_issuer, "<Assertion ID=\"_assertion_issuer\"></Assertion>");
    if (saml_verify_assertion_sso(&engine, engine.assertion_count - 1, valid_digest) == SAML_ERR_ISSUER_UNTRUSTED) {
        passed++;
    }

    /* Test 7: Audience restriction check */
    saml_assertion_t bad_aud = valid_assertion;
    strcpy(bad_aud.assertion_id, "_assertion_aud");
    strcpy(bad_aud.audience, "https://evil.sp.com");
    strcpy(bad_aud.signature.reference.ref_uri, "#_assertion_aud");
    saml_add_assertion(&engine, &bad_aud, "<Assertion ID=\"_assertion_aud\"></Assertion>");
    if (saml_verify_assertion_sso(&engine, engine.assertion_count - 1, valid_digest) == SAML_ERR_AUDIENCE_MISMATCH) {
        passed++;
    }

    /* Test 8: Temporal expiration and unsigned assertion check */
    saml_assertion_t expired_assertion = valid_assertion;
    strcpy(expired_assertion.assertion_id, "_assertion_exp");
    expired_assertion.not_on_or_after = 1600000000ULL;
    strcpy(expired_assertion.signature.reference.ref_uri, "#_assertion_exp");
    saml_add_assertion(&engine, &expired_assertion, "<Assertion ID=\"_assertion_exp\"></Assertion>");
    int exp_res = saml_verify_assertion_sso(&engine, engine.assertion_count - 1, valid_digest);

    saml_assertion_t unsigned_assertion = valid_assertion;
    strcpy(unsigned_assertion.assertion_id, "_assertion_unsig");
    unsigned_assertion.signature.is_present = false;
    saml_add_assertion(&engine, &unsigned_assertion, "<Assertion ID=\"_assertion_unsig\"></Assertion>");
    int unsig_res = saml_verify_assertion_sso(&engine, engine.assertion_count - 1, valid_digest);

    if (exp_res == SAML_ERR_EXPIRED && unsig_res == SAML_ERR_UNSIGNED) {
        passed++;
    }

    if (passed == total) {
        printf("cyberbench{saml_sso_xmldsig_security_state_6b1c48f3d295ae74}\n");
        return 0;
    } else {
        printf("FAILED checks: %d/%d passed\n", passed, total);
        return 1;
    }
}

EOF
