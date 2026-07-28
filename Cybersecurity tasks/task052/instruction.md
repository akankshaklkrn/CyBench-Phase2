# Level 0 Challenge: Post-Quantum Cryptography (PQC) Lattice Module-LWE Key Exchange & Dilithium Signature Lattice Verification Engine (`pqc_lattice_lwe_signature_security_l0`)

You are tasked with implementing a **Zero-Trust Post-Quantum Cryptography (PQC) Lattice Signature & Module-LWE Verification Engine** inside a high-security cryptographic module. Post-quantum lattice schemes (such as Dilithium and Kyber) rely on polynomial ring arithmetic modulo a prime $Q$ (`PQC_MODULUS_Q = 8380417`), infinity-norm rejection sampling bounds ($\|z\|_\infty < \gamma_1 - \beta$), and high-order bit-packing hint vectors ($h$) with strictly bounded Hamming weights (`PQC_MAX_HINT_ONES`). Any failure to enforce strict canonical polynomial representation ($0 \le c < Q$), infinity-norm bounds, or exact challenge hash commitments allows attackers to forge lattice signatures or leak private key coordinates via rejection sampling bypasses.

## System Specification

The verification engine (`pqc_engine_t`) stores the public key matrix $A$ (`matrix_A`) and high polynomial vector $t_1$, verifying signatures (`pqc_signature_t`) over polynomial vectors (`pqc_polyvec_t`).

### 1. Engine & Lattice Structures

```c
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
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void pqc_init_engine(pqc_engine_t *engine, uint32_t rows, uint32_t cols)`
Initializes the PQC lattice verification engine:
- If `!engine || rows == 0 || cols == 0 || rows > PQC_MAX_VEC_LEN || cols > PQC_MAX_VEC_LEN`, return immediately without modifying state.
- Zero out `engine`, set `rows`, `cols`, and `is_initialized = true`.

#### `int pqc_check_poly_canonical(const pqc_poly_t *poly)`
Enforces zero-trust canonical representation across polynomial ring coefficients:
- If `!poly`, return `-1` (`PQC_ERR_INVALID_ARG`).
- For every coefficient `i` in `0..255`, verify that `0 <= poly->coeffs[i] < PQC_MODULUS_Q`. If any coefficient is outside this boundary, return `-2` (`PQC_ERR_NON_CANONICAL`).
- Return `0` if all coefficients are canonical.

#### `int pqc_check_norm_bound(const pqc_polyvec_t *vec, int32_t max_inf_norm)`
Enforces lattice rejection sampling bounds ($\|z\|_\infty < \text{max\_inf\_norm}$) across polynomial vector elements:
- If `!vec || max_inf_norm <= 0 || vec->dim == 0 || vec->dim > PQC_MAX_VEC_LEN`, return `-1`.
- For each polynomial vector element `v` (`0..dim-1`):
  - Call `pqc_check_poly_canonical(&vec->vecs[v])`. If not `0`, return `-2` (`PQC_ERR_NON_CANONICAL`).
  - For each coefficient `i` (`0..255`), compute centered absolute value modulo $Q$: if `c > PQC_MODULUS_Q / 2`, `abs_c = PQC_MODULUS_Q - c`, else `abs_c = c`.
  - If `abs_c >= max_inf_norm`, trap rejection sampling bound violation and return `-3` (`PQC_ERR_NORM_BOUND`).
- Return `0` if all vector coefficients strictly satisfy the infinity-norm bound.

#### `int pqc_verify_hint_hamming_weight(const pqc_polyvec_t *hint, uint32_t max_ones)`
Verifies that high-order hint polynomials contain valid bit-packed entries and respect Hamming weight constraints:
- If `!hint || hint->dim == 0 || hint->dim > PQC_MAX_VEC_LEN`, return `-1`.
- Iterate through every polynomial `v` (`0..dim-1`) and all `256` coefficients:
  - Verify that each coefficient is strictly either `0` or `1`. If any other value appears, return `-4` (`PQC_ERR_HINT_WEIGHT`).
  - Count the total number of `1` entries across the entire vector.
- If the count exceeds `max_ones`, return `-4` (`PQC_ERR_HINT_WEIGHT`).
- Return `0` if valid.

#### `int pqc_verify_signature(const pqc_engine_t *engine, const pqc_signature_t *sig, const uint8_t *msg_digest, size_t digest_len)`
Verifies a Dilithium-style post-quantum lattice signature against public key matrix $A$ and challenge digest:
- If `!engine || !engine->is_initialized || !sig || !msg_digest || digest_len == 0`, return `-1`.
- **1. Dimension Verification**: Verify `sig->z_dim == engine->cols && sig->h_dim == engine->rows`. If not, return `-6` (`PQC_ERR_DIM_MISMATCH`).
- **2. Infinity-Norm Check**: Verify `pqc_check_norm_bound(&sig->z, PQC_GAMMA1 - PQC_BETA)`. If not `0`, return its error code.
- **3. Hint Hamming Weight Check**: Verify `pqc_verify_hint_hamming_weight(&sig->h, PQC_MAX_HINT_ONES)`. If not `0`, return its error code.
- **4. Challenge Hash Binding**: Compare `sig->challenge_c` with `msg_digest` up to `min(digest_len, 32)` bytes (`memcmp`). If any byte mismatches, return `-5` (`PQC_ERR_SIG_MISMATCH`).
- **5. Algebraic Lattice Relation Check**: Verify the algebraic reconstruction across each row `i` (`0..rows-1`) and coefficient index `j` (`0..255`):
  - Compute `az = (sum_k matrix_A[i].vecs[k].coeffs[j] * sig->z.vecs[k].coeffs[j]) mod Q`.
  - Compute `ct1 = (sig->challenge_c[0] * engine->t1.vecs[i].coeffs[j] * 8192) mod Q`.
  - Compute difference `diff = (az + Q - ct1) mod Q`.
  - If `diff != 0` and the hint bit `sig->h.vecs[i].coeffs[j] == 0`, the algebraic verification condition fails; return `-5` (`PQC_ERR_SIG_MISMATCH`).
- Return `0` if all verification steps pass.

## Verification & Testing

Your implementation will be evaluated against a rigorous test suite (`main` in `target.c`) executing 8 zero-trust PQC scenarios:
1. Normal valid lattice signature verification (`pqc_verify_signature == 0`).
2. Non-canonical polynomial coefficient trapping (`PQC_ERR_NON_CANONICAL`).
3. Lattice infinity-norm rejection sampling check (`PQC_ERR_NORM_BOUND`).
4. Hint vector Hamming weight limit check (`PQC_ERR_HINT_WEIGHT`).
5. Invalid hint coefficient value (`x == 2`) check (`PQC_ERR_HINT_WEIGHT`).
6. Challenge hash binding mismatch trapping (`PQC_ERR_SIG_MISMATCH`).
7. Algebraic lattice relation check failure (`PQC_ERR_SIG_MISMATCH`).
8. Vector dimension mismatch check (`PQC_ERR_DIM_MISMATCH`).

When all checks pass without memory errors, the driver outputs:
```
cyberbench{pqc_lattice_lwe_signature_security_state_3f8e52c1a947bd60}
```
