# Level 0 Challenge: Zero-Trust Zero-Knowledge Proof Arithmetic Circuit & Plonk/R1CS Verification Engine (`zerokey_zkp_circuit_verifier_security_l0`)

You are tasked with implementing a **Zero-Trust Zero-Knowledge Proof (ZKP) Arithmetic Circuit & Plonk/R1CS Verification Engine** inside a high-security cryptographic verifier module. Zero-knowledge proof systems verify arithmetic circuits composed of addition (`GATE_OP_ADD`), multiplication (`GATE_OP_MUL`), and constant (`GATE_OP_CONST`) gates over a prime finite field `ZKP_PRIME_P`. The verifier must check wire evaluations (`wire_evals`), polynomial commitments (`comm_a`, `comm_b`, `comm_c`, `comm_z`), public input binding (`public_inputs`), sponge hashing (`sponge_state`), and copy constraint permutation polynomial identities (`eval_z` vs `eval_z_next`). Any failure to enforce non-canonical field boundaries (`x >= ZKP_PRIME_P`), integer overflow safety, or gate constraint arithmetic allows attackers to forge proofs and bypass zero-knowledge authentication.

## System Specification

The verification engine (`zkp_circuit_t`) stores circuit gates (`gates`), wire configurations, public inputs, and cryptographic sponge absorption state across finite field evaluations (`zkp_proof_t`).

### 1. Engine & Proof Structures

```c
#define ZKP_PRIME_P 0x7FFFFFFFULL
#define ZKP_MAX_WIRES 16
#define ZKP_MAX_GATES 32
#define ZKP_MAX_SPONGE_WORDS 64

typedef enum {
    GATE_OP_ADD = 1,  /* (q_l * w_l + q_r * w_r + P - w_o) mod P == 0 */
    GATE_OP_MUL = 2,  /* (q_m * ((w_l * w_r) mod P) + P - w_o) mod P == 0 */
    GATE_OP_CONST = 3 /* (w_l + P - (q_c mod P)) mod P == 0 */
} gate_op_t;

typedef struct {
    gate_op_t op;
    uint32_t left_wire;
    uint32_t right_wire;
    uint32_t out_wire;
    uint64_t q_l;
    uint64_t q_r;
    uint64_t q_m;
    uint64_t q_c;
} zkp_gate_t;

typedef struct {
    uint64_t wire_evals[ZKP_MAX_WIRES];
    uint32_t wire_count;
    uint64_t comm_a;
    uint64_t comm_b;
    uint64_t comm_c;
    uint64_t comm_z;
    uint64_t eval_a;
    uint64_t eval_b;
    uint64_t eval_c;
    uint64_t eval_z;
    uint64_t eval_z_next;
} zkp_proof_t;

typedef struct {
    zkp_gate_t gates[ZKP_MAX_GATES];
    uint32_t gate_count;
    uint32_t num_wires;
    uint32_t num_public_inputs;
    uint64_t public_inputs[ZKP_MAX_WIRES];
    uint64_t sponge_words[ZKP_MAX_SPONGE_WORDS];
    uint32_t sponge_count;
    uint64_t sponge_state;
    bool is_initialized;
} zkp_circuit_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void zkp_init_circuit(zkp_circuit_t *circuit, uint32_t num_wires, uint32_t num_public, const uint64_t *pub_inputs)`
Initializes the ZKP circuit engine:
- If `!circuit` or `num_wires > ZKP_MAX_WIRES` or `num_public > num_wires`, return without modifying state.
- Zero out `circuit`, set `num_wires` and `num_public_inputs`.
- If `pub_inputs && num_public > 0`, copy each public input modulo `ZKP_PRIME_P` (`pub_inputs[i] % ZKP_PRIME_P`).
- Initialize `sponge_state = 0x1234567890ABCDEFULL % ZKP_PRIME_P` and set `is_initialized = true`.

#### `int zkp_add_gate(zkp_circuit_t *circuit, gate_op_t op, uint32_t left, uint32_t right, uint32_t out, uint64_t q_l, uint64_t q_r, uint64_t q_m, uint64_t q_c)`
Adds a gate constraint to the arithmetic circuit:
- If `!circuit || !circuit->is_initialized` or wire indices out of bounds (`left >= num_wires || right >= num_wires || out >= num_wires`), return `-1` (`ZKP_ERR_INVALID_ARG`).
- If `gate_count >= ZKP_MAX_GATES`, return `-2` (`ZKP_ERR_TABLE_FULL`).
- Store `op`, `left_wire`, `right_wire`, `out_wire`, and coefficients reduced modulo `ZKP_PRIME_P` (`q_l % ZKP_PRIME_P`, etc.). Increment `gate_count` and return `0`.

#### `int zkp_sponge_absorb(zkp_circuit_t *circuit, const uint64_t *elements, size_t count)`
Absorbs field elements into the cryptographic sponge for Fiat-Shamir challenge generation:
- If `!circuit || !circuit->is_initialized || (!elements && count > 0)`, return `-1`.
- For each element in `elements[0..count-1]`:
  - If `sponge_count >= ZKP_MAX_SPONGE_WORDS`, return `-3` (`ZKP_ERR_SPONGE_FULL`).
  - Store `elem = elements[i] % ZKP_PRIME_P` in `sponge_words[sponge_count++]`.
  - Update finite field sponge mixing: `circuit->sponge_state = ((circuit->sponge_state ^ elem) * 0x01000193ULL) % ZKP_PRIME_P`.
- Return `0`.

#### `int zkp_verify_field_canonical(const zkp_proof_t *proof)`
Enforces zero-trust canonical representation across all proof field elements:
- If `!proof`, return `-1`.
- Check whether any polynomial commitments (`comm_a`, `comm_b`, `comm_c`, `comm_z`) or polynomial evaluations (`eval_a`, `eval_b`, `eval_c`, `eval_z`, `eval_z_next`) are `>= ZKP_PRIME_P`. If so, trap as non-canonical and return `-4` (`ZKP_ERR_NON_CANONICAL`).
- Check whether any wire evaluation (`wire_evals[0..wire_count-1]`) is `>= ZKP_PRIME_P`. If so, return `-4`.
- Return `0` if all elements are strictly `< ZKP_PRIME_P`.

#### `int zkp_verify_circuit_satisfaction(const zkp_circuit_t *circuit, const zkp_proof_t *proof, uint64_t challenge_beta, uint64_t challenge_gamma)`
Verifies public input binding, arithmetic gate satisfaction, and Plonk copy constraints:
- If `!circuit || !circuit->is_initialized || !proof || proof->wire_count != circuit->num_wires`, return `-1`.
- **1. Canonical Field Check**: Call `zkp_verify_field_canonical(proof)`. If not `0`, return its error code.
- **2. Public Input Binding Check**: Verify that `proof->wire_evals[i] == circuit->public_inputs[i]` for `i` in `0..num_public_inputs-1`. If any mismatch, return `-5` (`ZKP_ERR_PUBLIC_MISMATCH`).
- **3. Arithmetic Gate Check**: For each gate `g` in `gates[0..gate_count-1]`:
  - Let `w_l = wire_evals[left_wire]`, `w_r = wire_evals[right_wire]`, `w_o = wire_evals[out_wire]`.
  - If `GATE_OP_ADD`: `((q_l * w_l) % P + (q_r * w_r) % P) % P == w_o`. If not equal, return `-6` (`ZKP_ERR_GATE_UNSAT`).
  - If `GATE_OP_MUL`: `(q_m * ((w_l * w_r) % P)) % P == w_o`. If not equal, return `-6`.
  - If `GATE_OP_CONST`: `w_l == q_c`. If not equal, return `-6`.
- **4. Copy Constraint Permutation Polynomial Identity**:
  - Let `beta = challenge_beta % P`, `gamma = challenge_gamma % P`.
  - Compute `t1 = (eval_a + beta + gamma) % P` and `lhs = (t1 * eval_z) % P`.
  - Compute `t2 = (eval_b + ((beta * 2) % P) + gamma) % P` and `rhs = (t2 * eval_z_next) % P`.
  - If `lhs != rhs`, return `-7` (`ZKP_ERR_COPY_CONSTRAINT`).
- Return `0` if all verification constraints pass.

## Verification & Testing

Your implementation will be evaluated against a rigorous test suite (`main` in `target.c`) executing 8 zero-trust ZKP scenarios:
1. Normal arithmetic circuit and Plonk proof verification (`zkp_verify_circuit_satisfaction == 0`).
2. Non-canonical polynomial commitment trapping (`comm_a = ZKP_PRIME_P + 5` returns `ZKP_ERR_NON_CANONICAL`).
3. Non-canonical wire evaluation trapping (`wire_evals[2] = ZKP_PRIME_P` returns `ZKP_ERR_NON_CANONICAL`).
4. Public input binding mismatch check (`wire_evals[0] != public_inputs[0]` returns `ZKP_ERR_PUBLIC_MISMATCH`).
5. `GATE_OP_ADD` arithmetic constraint violation check.
6. `GATE_OP_MUL` multiplication constraint violation check.
7. Copy constraint permutation identity violation check (`lhs != rhs` returns `ZKP_ERR_COPY_CONSTRAINT`).
8. Cryptographic sponge absorption state determinism and mixing check.

When all zero-trust checks pass cleanly without memory errors, the driver outputs:
```
cyberbench{zerokey_zkp_circuit_verifier_security_state_8c72b15e4f901a3c}
```
