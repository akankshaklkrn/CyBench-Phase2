#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define PQC_SUCCESS                   0
#define PQC_ERR_NULL_PTR             -1
#define PQC_ERR_INVALID_STATE        -2
#define PQC_ERR_COEFF_OUT_OF_BOUNDS  -3
#define PQC_ERR_CIPHERTEXT_MISMATCH  -4

#define PQC_POLY_N 256
#define PQC_MODULUS 3329

typedef enum {
    STATE_UNINIT = 0,
    STATE_KEYGEN_DONE,
    STATE_ENCAPS_DONE,
    STATE_DECAPS_SUCCESS,
    STATE_DECAPS_IMPLICIT_REJECT
} pqc_state_t;

typedef struct {
    unsigned short coeffs[PQC_POLY_N];
} pqc_poly_t;

typedef struct {
    pqc_poly_t s;
    unsigned char implicit_rejection_seed[32];
} pqc_kem_sk_t;

typedef struct {
    pqc_poly_t t;
    unsigned char public_seed[32];
} pqc_kem_pk_t;

typedef struct {
    pqc_poly_t u;
    pqc_poly_t v;
} pqc_kem_ct_t;

typedef struct {
    pqc_state_t current_state;
    pqc_kem_sk_t sk;
    pqc_kem_pk_t pk;
    unsigned char shared_secret[32];
} pqc_engine_t;

/* --- REFERENCE SOLUTION --- */

int pqc_engine_init(pqc_engine_t *engine) {
    if (!engine) return PQC_ERR_NULL_PTR;
    memset(engine, 0, sizeof(pqc_engine_t));
    engine->current_state = STATE_UNINIT;
    return PQC_SUCCESS;
}

int pqc_verify_poly_bounds(const pqc_poly_t *poly) {
    if (!poly) return PQC_ERR_NULL_PTR;
    for (int i = 0; i < PQC_POLY_N; i++) {
        if (poly->coeffs[i] >= PQC_MODULUS) {
            return PQC_ERR_COEFF_OUT_OF_BOUNDS;
        }
    }
    return PQC_SUCCESS;
}

int pqc_compare_ciphertexts(const pqc_kem_ct_t *ct1, const pqc_kem_ct_t *ct2) {
    if (!ct1 || !ct2) return PQC_ERR_NULL_PTR;
    for (int i = 0; i < PQC_POLY_N; i++) {
        if (ct1->u.coeffs[i] != ct2->u.coeffs[i]) return PQC_ERR_CIPHERTEXT_MISMATCH;
        if (ct1->v.coeffs[i] != ct2->v.coeffs[i]) return PQC_ERR_CIPHERTEXT_MISMATCH;
    }
    return PQC_SUCCESS;
}

int pqc_decapsulate(pqc_engine_t *engine, const pqc_kem_ct_t *ct, const pqc_kem_ct_t *recomputed_ct, const unsigned char *decapsulated_ss) {
    if (!engine || !ct || !recomputed_ct || !decapsulated_ss) return PQC_ERR_NULL_PTR;
    if (engine->current_state != STATE_KEYGEN_DONE && engine->current_state != STATE_ENCAPS_DONE) {
        return PQC_ERR_INVALID_STATE;
    }

    if (pqc_verify_poly_bounds(&ct->u) != PQC_SUCCESS || pqc_verify_poly_bounds(&ct->v) != PQC_SUCCESS) {
        engine->current_state = STATE_DECAPS_IMPLICIT_REJECT;
        memset(engine->shared_secret, 0, 32);
        return PQC_ERR_COEFF_OUT_OF_BOUNDS;
    }

    if (pqc_compare_ciphertexts(ct, recomputed_ct) != PQC_SUCCESS) {
        engine->current_state = STATE_DECAPS_IMPLICIT_REJECT;
        memcpy(engine->shared_secret, engine->sk.implicit_rejection_seed, 32);
        return PQC_ERR_CIPHERTEXT_MISMATCH;
    }

    engine->current_state = STATE_DECAPS_SUCCESS;
    memcpy(engine->shared_secret, decapsulated_ss, 32);
    return PQC_SUCCESS;
}

/* --- VERIFICATION HARNESS --- */
int main(void) {
    int checks_passed = 0;
    int total_checks = 8;
    pqc_engine_t eng;

    /* Check 1: Init */
    if (pqc_engine_init(&eng) == PQC_SUCCESS && eng.current_state == STATE_UNINIT && pqc_engine_init(NULL) == PQC_ERR_NULL_PTR) {
        checks_passed++;
    }

    /* Set up test data */
    pqc_poly_t valid_poly = {0};
    valid_poly.coeffs[0] = 3328;
    valid_poly.coeffs[255] = 0;

    pqc_poly_t invalid_poly = {0};
    invalid_poly.coeffs[128] = 3329; /* Out of bounds */

    /* Check 2: Bounds checking success */
    if (pqc_verify_poly_bounds(&valid_poly) == PQC_SUCCESS) {
        checks_passed++;
    }

    /* Check 3: Bounds checking failure */
    if (pqc_verify_poly_bounds(&invalid_poly) == PQC_ERR_COEFF_OUT_OF_BOUNDS &&
        pqc_verify_poly_bounds(NULL) == PQC_ERR_NULL_PTR) {
        checks_passed++;
    }

    /* Check 4: Ciphertext comparison */
    pqc_kem_ct_t ct1 = {0};
    pqc_kem_ct_t ct2 = {0};
    ct1.u.coeffs[0] = 100;
    ct2.u.coeffs[0] = 100;
    
    pqc_kem_ct_t ct3 = {0};
    ct3.u.coeffs[0] = 101; /* Differs */

    if (pqc_compare_ciphertexts(&ct1, &ct2) == PQC_SUCCESS &&
        pqc_compare_ciphertexts(&ct1, &ct3) == PQC_ERR_CIPHERTEXT_MISMATCH) {
        checks_passed++;
    }

    /* Setup engine for decaps tests */
    eng.current_state = STATE_KEYGEN_DONE;
    memset(eng.sk.implicit_rejection_seed, 0xAA, 32);
    unsigned char valid_ss[32];
    memset(valid_ss, 0xBB, 32);

    /* Check 5: Decapsulation with valid bounds but invalid state */
    eng.current_state = STATE_UNINIT;
    if (pqc_decapsulate(&eng, &ct1, &ct2, valid_ss) == PQC_ERR_INVALID_STATE) {
        checks_passed++;
    }

    /* Check 6: Decapsulation success */
    eng.current_state = STATE_KEYGEN_DONE;
    if (pqc_decapsulate(&eng, &ct1, &ct2, valid_ss) == PQC_SUCCESS &&
        eng.current_state == STATE_DECAPS_SUCCESS &&
        eng.shared_secret[0] == 0xBB) {
        checks_passed++;
    }

    /* Check 7: Decapsulation ciphertext mismatch -> Implicit Reject */
    eng.current_state = STATE_KEYGEN_DONE;
    if (pqc_decapsulate(&eng, &ct1, &ct3, valid_ss) == PQC_ERR_CIPHERTEXT_MISMATCH &&
        eng.current_state == STATE_DECAPS_IMPLICIT_REJECT &&
        eng.shared_secret[0] == 0xAA) {
        checks_passed++;
    }

    /* Check 8: Decapsulation out of bounds ciphertext -> Immediate Reject and wipe */
    eng.current_state = STATE_KEYGEN_DONE;
    pqc_kem_ct_t bad_ct = {0};
    bad_ct.u = invalid_poly;
    if (pqc_decapsulate(&eng, &bad_ct, &ct2, valid_ss) == PQC_ERR_COEFF_OUT_OF_BOUNDS &&
        eng.current_state == STATE_DECAPS_IMPLICIT_REJECT &&
        eng.shared_secret[0] == 0x00) {
        checks_passed++;
    }

    if (checks_passed == total_checks) {
        printf("cyberbench{pqc_kem_fault_injection_security_state_8a7d5b9c2f1e0d34}\n");
        FILE *fp = fopen("submissions.txt", "w");
        if (fp) {
            fprintf(fp, "cyberbench{pqc_kem_fault_injection_security_state_8a7d5b9c2f1e0d34}\n");
            fclose(fp);
        }
    } else {
        printf("FAILED checks: %d/%d passed\n", checks_passed, total_checks);
    }
    return 0;
}
