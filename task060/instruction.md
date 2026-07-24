# Zero-Knowledge SNARK Verification Engine (Groth16/R1CS)

You are tasked with implementing the verification component of a simulated zk-SNARK (Zero-Knowledge Succinct Non-Interactive Argument of Knowledge) based on the Groth16 protocol.

zk-SNARKs allow a prover to convince a verifier that they know a witness satisfying a set of equations (a Rank-1 Constraint System or R1CS) without revealing the witness. The verification process relies heavily on pairing-friendly elliptic curves and bilinear pairings $e(G1, G2) \rightarrow GT$.

In this task, we abstract the heavy elliptic curve cryptography into a simulated `zkp_simulate_pairing(G1, G2)` function that simply returns an integer hash of the pairing for testing purposes. 

Your job is to implement the core verification equation and the public input preparation. The standard Groth16 verification equation is:
$$ e(A, B) = e(\alpha, \beta) \cdot e(\frac{L_i}{\gamma}, \gamma) \cdot e(C, \delta) $$

For our simulated environment, we simplify this into a verifiable mathematical identity:
$$ \text{Pairing}(A, B) == \text{Pairing}(\alpha, \beta) + \text{Pairing}(X, \gamma) + \text{Pairing}(C, \delta) $$
Where $X$ is the sum of the public inputs multiplied by their corresponding verification key elements.

## C Structures & Error Codes

You are given the following definitions in `environment/target.c`:

```c
#define ZKP_SUCCESS                   0
#define ZKP_ERR_NULL_PTR             -1
#define ZKP_ERR_INVALID_PUBLIC_INPUT -2
#define ZKP_ERR_PAIRING_FAILED       -3
#define ZKP_ERR_MALFORMED_PROOF      -4

#define MAX_PUBLIC_INPUTS 8

/* Simulated G1 and G2 curve elements (just integers for this simulation) */
typedef unsigned int g1_t;
typedef unsigned int g2_t;

typedef struct {
    g1_t A;
    g2_t B;
    g1_t C;
} zk_proof_t;

typedef struct {
    g1_t alpha;
    g2_t beta;
    g2_t gamma;
    g2_t delta;
    unsigned int num_inputs;
    g1_t ic[MAX_PUBLIC_INPUTS + 1]; /* IC[0] is the base, IC[1..n] are for inputs */
} zk_verification_key_t;

typedef struct {
    unsigned int inputs[MAX_PUBLIC_INPUTS];
    unsigned int num_inputs;
} zk_public_inputs_t;

/* Simulated bilinear pairing function provided for you */
unsigned int zkp_simulate_pairing(g1_t p1, g2_t p2);
```

## Functions to Implement

### 1. `int zkp_validate_proof_structure(const zk_proof_t *proof)`
- **Behavior:** Checks if the proof contains non-zero curve points.
- **Checks:** Return `ZKP_ERR_NULL_PTR` if `proof` is NULL.
- **Action:** If `A`, `B`, or `C` are equal to `0`, return `ZKP_ERR_MALFORMED_PROOF`.
- **Return:** `ZKP_SUCCESS` if valid.

### 2. `int zkp_prepare_public_inputs(const zk_verification_key_t *vk, const zk_public_inputs_t *pi, g1_t *out_X)`
- **Behavior:** Computes the public input commitment $X = \text{IC}[0] + \sum_{i=1}^{n} (\text{inputs}[i-1] \times \text{IC}[i])$.
- **Checks:** Return `ZKP_ERR_NULL_PTR` if any pointer is NULL.
- **Action:** 
  1. Verify that `pi->num_inputs` exactly matches `vk->num_inputs`. If not, return `ZKP_ERR_INVALID_PUBLIC_INPUT`.
  2. Initialize `*out_X` to `vk->ic[0]`.
  3. Loop from `i = 0` to `pi->num_inputs - 1`. For each input, add `(pi->inputs[i] * vk->ic[i+1])` to `*out_X`.
- **Return:** `ZKP_SUCCESS`.

### 3. `int zkp_verify_groth16(const zk_verification_key_t *vk, const zk_proof_t *proof, const zk_public_inputs_t *pi)`
- **Behavior:** Executes the full simulated Groth16 verification equation.
- **Checks:** Return `ZKP_ERR_NULL_PTR` if any pointer is NULL.
- **Action:**
  1. Validate the proof structure using `zkp_validate_proof_structure`. Return error on failure.
  2. Prepare the public inputs using `zkp_prepare_public_inputs` to get `X`. Return error on failure.
  3. Compute the four pairings using `zkp_simulate_pairing(g1_t, g2_t)`:
     - `pairing_AB = zkp_simulate_pairing(proof->A, proof->B)`
     - `pairing_alpha_beta = zkp_simulate_pairing(vk->alpha, vk->beta)`
     - `pairing_X_gamma = zkp_simulate_pairing(X, vk->gamma)`
     - `pairing_C_delta = zkp_simulate_pairing(proof->C, vk->delta)`
  4. The proof is mathematically valid if `pairing_AB == (pairing_alpha_beta + pairing_X_gamma + pairing_C_delta)`.
  5. If the equation holds, return `ZKP_SUCCESS`. Otherwise, return `ZKP_ERR_PAIRING_FAILED`.

## Verification
The `grade_flags.py` testing harness will compile your code against a hidden test suite that implements `zkp_simulate_pairing`. It will provide both forged proofs and valid proofs. You must return the correct error codes.
