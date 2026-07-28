#!/bin/bash
set -e
mkdir -p /src
cat << 'EOF' > /src/target.c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#define PQC_MODULUS_Q     8380417
#define PQC_POLY_DEGREE   256
#define PQC_MAX_VEC_LEN   4
#define PQC_MAX_HINT_ONES 80
#define PQC_GAMMA1        524288 /* 2^19 */
#define PQC_BETA          196

typedef struct {
    int32_t coeffs[PQC_POLY_DEGREE];
} pqc_poly_t;

typedef struct {
    pqc_poly_t vecs[PQC_MAX_VEC_LEN];
    uint32_t   dim;
} pqc_polyvec_t;

typedef struct {
    pqc_polyvec_t z;               /* Response vector */
    pqc_polyvec_t h;               /* High-order hint vector */
    uint8_t       challenge_c[32]; /* Shake-256 hash of commitment and message */
    uint32_t      z_dim;
    uint32_t      h_dim;
} pqc_signature_t;

typedef struct {
    pqc_polyvec_t matrix_A[PQC_MAX_VEC_LEN]; /* Public key matrix A */
    pqc_polyvec_t t1;                        /* High part of public key t = A*s */
    uint32_t      rows;
    uint32_t      cols;
    bool          is_initialized;
} pqc_engine_t;

/* Error codes */
#define PQC_ERR_INVALID_ARG    -1
#define PQC_ERR_NON_CANONICAL  -2 /* Coefficient outside [0, Q-1] */
#define PQC_ERR_NORM_BOUND     -3 /* ||z||_inf >= gamma1 - beta (Lattice vector leakage / rejection sampling violation) */
#define PQC_ERR_HINT_WEIGHT    -4 /* Hamming weight of hint vector exceeds max allowed */
#define PQC_ERR_SIG_MISMATCH   -5 /* Algebraic lattice verification equation failure */
#define PQC_ERR_DIM_MISMATCH   -6

void pqc_init_engine(pqc_engine_t *engine, uint32_t rows, uint32_t cols) {
    if (!engine || rows == 0 || cols == 0 || rows > PQC_MAX_VEC_LEN || cols > PQC_MAX_VEC_LEN) return;
    memset(engine, 0, sizeof(pqc_engine_t));
    engine->rows = rows;
    engine->cols = cols;
    engine->is_initialized = true;
}

int pqc_check_poly_canonical(const pqc_poly_t *poly) {
    if (!poly) return PQC_ERR_INVALID_ARG;
    for (int i = 0; i < PQC_POLY_DEGREE; i++) {
        if (poly->coeffs[i] < 0 || poly->coeffs[i] >= PQC_MODULUS_Q) {
            return PQC_ERR_NON_CANONICAL;
        }
    }
    return 0;
}

int pqc_check_norm_bound(const pqc_polyvec_t *vec, int32_t max_inf_norm) {
    if (!vec || max_inf_norm <= 0 || vec->dim == 0 || vec->dim > PQC_MAX_VEC_LEN) return PQC_ERR_INVALID_ARG;
    for (uint32_t v = 0; v < vec->dim; v++) {
        int canon = pqc_check_poly_canonical(&vec->vecs[v]);
        if (canon != 0) return canon;
        for (int i = 0; i < PQC_POLY_DEGREE; i++) {
            int32_t c = vec->vecs[v].coeffs[i];
            int32_t abs_c = (c > PQC_MODULUS_Q / 2) ? (PQC_MODULUS_Q - c) : c;
            if (abs_c >= max_inf_norm) {
                return PQC_ERR_NORM_BOUND;
            }
        }
    }
    return 0;
}

int pqc_verify_hint_hamming_weight(const pqc_polyvec_t *hint, uint32_t max_ones) {
    if (!hint || hint->dim == 0 || hint->dim > PQC_MAX_VEC_LEN) return PQC_ERR_INVALID_ARG;
    uint32_t count = 0;
    for (uint32_t v = 0; v < hint->dim; v++) {
        for (int i = 0; i < PQC_POLY_DEGREE; i++) {
            int32_t val = hint->vecs[v].coeffs[i];
            if (val != 0 && val != 1) {
                return PQC_ERR_HINT_WEIGHT;
            }
            if (val == 1) {
                count++;
            }
        }
    }
    if (count > max_ones) {
        return PQC_ERR_HINT_WEIGHT;
    }
    return 0;
}

int pqc_verify_signature(const pqc_engine_t *engine, const pqc_signature_t *sig, const uint8_t *msg_digest, size_t digest_len) {
    if (!engine || !engine->is_initialized || !sig || !msg_digest || digest_len == 0) return PQC_ERR_INVALID_ARG;
    if (sig->z_dim != engine->cols || sig->h_dim != engine->rows) {
        return PQC_ERR_DIM_MISMATCH;
    }

    int norm_check = pqc_check_norm_bound(&sig->z, PQC_GAMMA1 - PQC_BETA);
    if (norm_check != 0) return norm_check;

    int hint_check = pqc_verify_hint_hamming_weight(&sig->h, PQC_MAX_HINT_ONES);
    if (hint_check != 0) return hint_check;

    size_t cmp_len = (digest_len < 32) ? digest_len : 32;
    if (memcmp(sig->challenge_c, msg_digest, cmp_len) != 0) {
        return PQC_ERR_SIG_MISMATCH;
    }

    uint64_t c_val = sig->challenge_c[0] % PQC_MODULUS_Q;
    for (uint32_t i = 0; i < engine->rows; i++) {
        for (int j = 0; j < PQC_POLY_DEGREE; j++) {
            uint64_t az = 0;
            for (uint32_t k = 0; k < engine->cols; k++) {
                az = (az + (uint64_t)engine->matrix_A[i].vecs[k].coeffs[j] * sig->z.vecs[k].coeffs[j]) % PQC_MODULUS_Q;
            }
            uint64_t ct1 = ((uint64_t)c_val * engine->t1.vecs[i].coeffs[j] * 8192ULL) % PQC_MODULUS_Q;
            uint64_t diff = (az + PQC_MODULUS_Q - ct1) % PQC_MODULUS_Q;
            if (diff != 0 && sig->h.vecs[i].coeffs[j] == 0) {
                return PQC_ERR_SIG_MISMATCH;
            }
        }
    }
    return 0;
}

/* Verification test suite in main() */
int main(void) {
    pqc_engine_t engine;
    pqc_init_engine(&engine, 2, 2);
    engine.matrix_A[0].dim = 2;
    engine.matrix_A[1].dim = 2;
    engine.t1.dim = 2;

    /* Setup identity relation where A*z == c*t1*8192 mod Q so diff == 0 */
    engine.matrix_A[0].vecs[0].coeffs[0] = 1;
    engine.t1.vecs[0].coeffs[0] = 1;

    pqc_signature_t sig;
    memset(&sig, 0, sizeof(sig));
    sig.z_dim = 2;
    sig.h_dim = 2;
    sig.z.dim = 2;
    sig.h.dim = 2;
    sig.challenge_c[0] = 5;
    /* z[0][0] = 5 * 1 * 8192 = 40960 so az = 40960, ct1 = 40960 */
    sig.z.vecs[0].coeffs[0] = 40960;

    uint8_t digest[32];
    memset(digest, 0, sizeof(digest));
    digest[0] = 5;

    int passed = 0;
    int total = 8;

    /* Test 1: Normal valid signature verification */
    if (pqc_verify_signature(&engine, &sig, digest, sizeof(digest)) == 0) {
        passed++;
    }

    /* Test 2: Non-canonical polynomial coefficient check */
    pqc_signature_t bad_canon = sig;
    bad_canon.z.vecs[0].coeffs[1] = PQC_MODULUS_Q + 10;
    if (pqc_verify_signature(&engine, &bad_canon, digest, sizeof(digest)) == PQC_ERR_NON_CANONICAL) {
        passed++;
    }

    /* Test 3: Lattice infinity-norm bound check (rejection sampling failure) */
    pqc_signature_t bad_norm = sig;
    bad_norm.z.vecs[0].coeffs[1] = PQC_GAMMA1 - PQC_BETA + 100;
    if (pqc_verify_signature(&engine, &bad_norm, digest, sizeof(digest)) == PQC_ERR_NORM_BOUND) {
        passed++;
    }

    /* Test 4: Hint vector Hamming weight limit check */
    pqc_signature_t bad_hint_weight = sig;
    for (int i = 0; i < 85; i++) {
        bad_hint_weight.h.vecs[0].coeffs[i] = 1;
    }
    if (pqc_verify_signature(&engine, &bad_hint_weight, digest, sizeof(digest)) == PQC_ERR_HINT_WEIGHT) {
        passed++;
    }

    /* Test 5: Invalid hint coefficient value check */
    pqc_signature_t bad_hint_val = sig;
    bad_hint_val.h.vecs[0].coeffs[5] = 2;
    if (pqc_verify_signature(&engine, &bad_hint_val, digest, sizeof(digest)) == PQC_ERR_HINT_WEIGHT) {
        passed++;
    }

    /* Test 6: Challenge hash binding mismatch check */
    uint8_t bad_digest[32];
    memset(bad_digest, 0, sizeof(bad_digest));
    bad_digest[0] = 99;
    if (pqc_verify_signature(&engine, &sig, bad_digest, sizeof(bad_digest)) == PQC_ERR_SIG_MISMATCH) {
        passed++;
    }

    /* Test 7: Algebraic lattice relation check failure */
    pqc_signature_t bad_alg = sig;
    bad_alg.z.vecs[0].coeffs[0] = 12345; /* az != ct1 and h == 0 */
    if (pqc_verify_signature(&engine, &bad_alg, digest, sizeof(digest)) == PQC_ERR_SIG_MISMATCH) {
        passed++;
    }

    /* Test 8: Vector dimension check */
    pqc_signature_t bad_dim = sig;
    bad_dim.z_dim = 3;
    if (pqc_verify_signature(&engine, &bad_dim, digest, sizeof(digest)) == PQC_ERR_DIM_MISMATCH) {
        passed++;
    }

    if (passed == total) {
        printf("cyberbench{pqc_lattice_lwe_signature_security_state_3f8e52c1a947bd60}\n");
        return 0;
    } else {
        printf("FAILED checks: %d/%d passed\n", passed, total);
        return 1;
    }
}

EOF
