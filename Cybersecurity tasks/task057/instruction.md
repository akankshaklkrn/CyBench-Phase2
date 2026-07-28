# Post-Quantum KEM State Machine & CCA Security Simulator

You are tasked with implementing a critical state machine engine and bounds verifier for a simplified Post-Quantum Cryptography (PQC) Key Encapsulation Mechanism (KEM) similar to ML-KEM/Kyber.

In post-quantum KEMs, security against chosen-ciphertext attacks (IND-CCA2) is achieved by utilizing the Fujisaki-Okamoto (FO) transform. This transform requires an "implicit rejection" mechanism where the decapsulated secret is replaced with a pseudo-random value if the re-encrypted ciphertext does not perfectly match the provided ciphertext.

Additionally, lattice-based KEMs involve polynomial rings where coefficients must strictly fall within a specific mathematical modulo bound (e.g., $q = 3329$). Failure to enforce these bounds during decapsulation allows malicious actors to induce parsing faults, leading to key recovery attacks.

Your task is to implement the core KEM state transitions, polynomial coefficient bounds validation, and the FO implicit rejection fallback mechanism.

## C Structures & Error Codes

You are working with the following definitions in `environment/target.c` (or you can define them if missing):

```c
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
    unsigned short coeffs[PQC_POLY_N]; /* polynomial coefficients */
} pqc_poly_t;

typedef struct {
    pqc_poly_t s; /* secret polynomial */
    unsigned char implicit_rejection_seed[32];
} pqc_kem_sk_t;

typedef struct {
    pqc_poly_t t; /* public polynomial */
    unsigned char public_seed[32];
} pqc_kem_pk_t;

typedef struct {
    pqc_poly_t u; /* ciphertext component 1 */
    pqc_poly_t v; /* ciphertext component 2 */
} pqc_kem_ct_t;

typedef struct {
    pqc_state_t current_state;
    pqc_kem_sk_t sk;
    pqc_kem_pk_t pk;
    unsigned char shared_secret[32];
} pqc_engine_t;
```

## Functions to Implement

You must implement the following functions exactly as described:

### 1. `int pqc_engine_init(pqc_engine_t *engine)`
- **Behavior:** Initializes the engine.
- **Checks:** Return `PQC_ERR_NULL_PTR` if `engine` is NULL.
- **Action:** Memset the entire `engine` to 0. Set `current_state` to `STATE_UNINIT`.
- **Return:** `PQC_SUCCESS`.

### 2. `int pqc_verify_poly_bounds(const pqc_poly_t *poly)`
- **Behavior:** Checks if all coefficients in the polynomial are within the valid modulo range.
- **Checks:** Return `PQC_ERR_NULL_PTR` if `poly` is NULL.
- **Action:** Iterate through `poly->coeffs[0]` to `poly->coeffs[PQC_POLY_N - 1]`. If any coefficient is `>= PQC_MODULUS`, return `PQC_ERR_COEFF_OUT_OF_BOUNDS`.
- **Return:** `PQC_SUCCESS` if all coefficients are strictly less than `PQC_MODULUS`.

### 3. `int pqc_compare_ciphertexts(const pqc_kem_ct_t *ct1, const pqc_kem_ct_t *ct2)`
- **Behavior:** Performs a constant-time (or standard memcmp) comparison of two ciphertexts.
- **Checks:** Return `PQC_ERR_NULL_PTR` if either pointer is NULL.
- **Action:** Compare `ct1->u.coeffs` and `ct2->u.coeffs`, and `ct1->v.coeffs` and `ct2->v.coeffs`.
- **Return:** `PQC_SUCCESS` if they are perfectly identical. Return `PQC_ERR_CIPHERTEXT_MISMATCH` if any coefficient differs.

### 4. `int pqc_decapsulate(pqc_engine_t *engine, const pqc_kem_ct_t *ct, const pqc_kem_ct_t *recomputed_ct, const unsigned char *decapsulated_ss)`
- **Behavior:** Simulates the FO transform decapsulation and implicit rejection logic.
- **Checks:** Return `PQC_ERR_NULL_PTR` if any pointer is NULL.
- **State Check:** If `engine->current_state` is NOT `STATE_KEYGEN_DONE` and NOT `STATE_ENCAPS_DONE`, return `PQC_ERR_INVALID_STATE`.
- **Action:**
  1. Validate the bounds of `ct->u` and `ct->v` using `pqc_verify_poly_bounds`. If bounds check fails, **immediately transition** the engine state to `STATE_DECAPS_IMPLICIT_REJECT`, wipe the `engine->shared_secret` to 0, and return the bounds error.
  2. Compare the provided `ct` against the `recomputed_ct` using `pqc_compare_ciphertexts`.
  3. If there is a mismatch (simulating an active fault injection or invalid CCA ciphertext), **transition** the engine state to `STATE_DECAPS_IMPLICIT_REJECT`. Instead of copying the `decapsulated_ss`, copy the `engine->sk.implicit_rejection_seed` into `engine->shared_secret`. Return `PQC_ERR_CIPHERTEXT_MISMATCH`.
  4. If the comparison succeeds perfectly, **transition** the engine state to `STATE_DECAPS_SUCCESS`. Copy the `decapsulated_ss` (32 bytes) into `engine->shared_secret`. Return `PQC_SUCCESS`.

## Verification
A testing harness in `tests/grade_flags.py` will compile your code against a private `main()` test runner. You must implement the logic correctly inside `environment/target.c` such that the test runner prints the success flag. The runner expects no crashes, accurate bounds checking, and correct implicit rejection transitions.
