# Level 0 Challenge: Enterprise SAML 2.0 Single Sign-On (SSO) & XML Digital Signature (XMLDSig) Security Verification Engine (`saml_sso_xmldsig_security_l0`)

You are tasked with implementing a **Zero-Trust Enterprise SAML 2.0 Single Sign-On (SSO) & XML Digital Signature (XMLDSig) Security Verification Engine** inside an identity and access management gateway. SAML assertions (`saml_assertion_t`) authenticate enterprise users across service providers (`expected_audience`) and identity providers (`trusted_issuer`). Because SAML payloads rely on complex XML structures and XMLDSig references (`xmldsig_ref_t`), any vulnerability in canonicalization, digest verification, URI reference binding, or entity parsing allows attackers to execute **XML Signature Wrapping (XSW) attacks**, **XML External Entity (XXE) injections**, or assertion forgery bypasses.

## System Specification

The verification engine (`saml_engine_t`) stores valid assertions (`assertions`), expected audience constraints, trusted identity provider strings, and current time values for temporal window validation.

### 1. Engine & SAML Structures

```c
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
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void saml_init_engine(saml_engine_t *engine, const char *trusted_issuer, const char *expected_audience, uint64_t current_time)`
Initializes the SAML SSO engine:
- If `!engine || !trusted_issuer || !expected_audience`, return immediately without modifying state.
- Zero out `engine`, copy strings `trusted_issuer` and `expected_audience` up to `SAML_MAX_STR_LEN - 1` bytes (`strncpy`), set `current_time`, and set `is_initialized = true`.

#### `int saml_check_xxe_injection(const char *raw_xml)`
Enforces zero-trust XML External Entity (XXE) and DTD injection prevention:
- If `!raw_xml`, return `-1` (`SAML_ERR_INVALID_ARG`).
- Scan `raw_xml` for any occurrences of `<!DOCTYPE`, `<!ENTITY`, or `SYSTEM` keywords (`strstr`). If detected, trap XXE injection and return `-2` (`SAML_ERR_XXE_INJECTION`).
- Return `0` if clean.

#### `int saml_verify_xmldsig_digest(const xmldsig_ref_t *ref, const char *assertion_id, const uint8_t *computed_digest)`
Verifies XMLDSig canonical digests and traps XML Signature Wrapping (XSW) reference mismatch attacks:
- If `!ref || !assertion_id || !computed_digest`, return `-1`.
- **XSW Reference URI Binding Check**: Verify that `ref->ref_uri[0] == '#'` and `strcmp(ref->ref_uri + 1, assertion_id) == 0`. If the reference URI does not exactly point to `#` plus the assertion ID, trap XSW wrapping attack (`SAML_ERR_XSW_ATTACK`).
- Verify `ref->canon_method == CANON_EXCL_C14N`. If not, return `-4` (`SAML_ERR_DIGEST_MISMATCH`).
- Compare `ref->digest_val` with `computed_digest` (`memcmp` over `32` bytes). If mismatch, return `-4` (`SAML_ERR_DIGEST_MISMATCH`).
- Return `0`.

#### `int saml_add_assertion(saml_engine_t *engine, const saml_assertion_t *assertion, const char *raw_xml)`
Registers a SAML assertion into engine memory after performing safety checks:
- If `!engine || !engine->is_initialized || !assertion`, return `-1`.
- Verify `raw_xml` safety by calling `saml_check_xxe_injection(raw_xml)`. If not `0`, return `-2` (`SAML_ERR_XXE_INJECTION`).
- Check table capacity (`assertion_count >= SAML_MAX_ASSERTIONS` -> return `-1`).
- **XSW Duplicate ID Check**: Verify that no already registered assertion shares the same `assertion_id`. If `strcmp(engine->assertions[i].assertion_id, assertion->assertion_id) == 0`, trap duplicate ID XSW wrapping (`SAML_ERR_XSW_ATTACK`).
- Copy `*assertion` to `engine->assertions[assertion_count++]` and return `0`.

#### `int saml_verify_assertion_sso(saml_engine_t *engine, uint32_t assertion_index, const uint8_t *computed_digest)`
Performs comprehensive SSO validation on `engine->assertions[assertion_index]`:
- If `!engine || !engine->is_initialized || !computed_digest || assertion_index >= engine->assertion_count`, return `-1`.
- Let `a = &engine->assertions[assertion_index]`.
- **1. Signature Presence Check**: If `!a->signature.is_present`, return `-8` (`SAML_ERR_UNSIGNED`).
- **2. XMLDSig Digest & XSW Check**: Verify `saml_verify_xmldsig_digest(&a->signature.reference, a->assertion_id, computed_digest)`. If not `0`, return its error code.
- **3. Trusted Issuer Check**: Verify `strcmp(a->issuer, engine->trusted_issuer) == 0`. If mismatch, return `-7` (`SAML_ERR_ISSUER_UNTRUSTED`).
- **4. Audience Restriction Check**: Verify `strcmp(a->audience, engine->expected_audience) == 0`. If mismatch, return `-5` (`SAML_ERR_AUDIENCE_MISMATCH`).
- **5. Temporal Window Check**: Verify `engine->current_time >= a->not_before && engine->current_time <= a->not_on_or_after`. If outside this validity window, return `-6` (`SAML_ERR_EXPIRED`).
- If all checks succeed, mark `a->is_valid = true` and return `0`.

## Verification & Testing

Your implementation will be evaluated against a rigorous test suite (`main` in `target.c`) executing 8 zero-trust SAML/XMLDSig scenarios:
1. Normal valid SAML assertion SSO verification (`saml_verify_assertion_sso == 0`).
2. XML External Entity (`<!DOCTYPE foo SYSTEM "file:///etc/passwd">`) trapping (`SAML_ERR_XXE_INJECTION`).
3. XML Signature Wrapping (`ref_uri = "#_assertion_user"` vs `assertion_id = "_assertion_admin"`) trapping (`SAML_ERR_XSW_ATTACK`).
4. XML Signature Wrapping duplicate ID attempt check (`SAML_ERR_XSW_ATTACK`).
5. Canonical SHA-256 digest mismatch check (`SAML_ERR_DIGEST_MISMATCH`).
6. Untrusted identity provider check (`SAML_ERR_ISSUER_UNTRUSTED`).
7. Audience restriction mismatch check (`SAML_ERR_AUDIENCE_MISMATCH`).
8. Temporal window check (`SAML_ERR_EXPIRED`) and unsigned assertion trapping (`SAML_ERR_UNSIGNED`).

When all checks pass without memory errors, the driver outputs:
```
cyberbench{saml_sso_xmldsig_security_state_6b1c48f3d295ae74}
```
