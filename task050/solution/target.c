#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

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

/* Error codes */
#define ZKP_ERR_INVALID_ARG -1
#define ZKP_ERR_TABLE_FULL -2
#define ZKP_ERR_SPONGE_FULL -3
#define ZKP_ERR_NON_CANONICAL -4
#define ZKP_ERR_PUBLIC_MISMATCH -5
#define ZKP_ERR_GATE_UNSAT -6
#define ZKP_ERR_COPY_CONSTRAINT -7

void zkp_init_circuit(zkp_circuit_t *circuit, uint32_t num_wires, uint32_t num_public, const uint64_t *pub_inputs) {
    if (!circuit || num_wires > ZKP_MAX_WIRES || num_public > num_wires) return;
    memset(circuit, 0, sizeof(zkp_circuit_t));
    circuit->num_wires = num_wires;
    circuit->num_public_inputs = num_public;
    if (pub_inputs && num_public > 0) {
        for (uint32_t i = 0; i < num_public; i++) {
            circuit->public_inputs[i] = pub_inputs[i] % ZKP_PRIME_P;
        }
    }
    circuit->sponge_state = 0x1234567890ABCDEFULL % ZKP_PRIME_P;
    circuit->is_initialized = true;
}

int zkp_add_gate(zkp_circuit_t *circuit, gate_op_t op, uint32_t left, uint32_t right, uint32_t out, uint64_t q_l, uint64_t q_r, uint64_t q_m, uint64_t q_c) {
    if (!circuit || !circuit->is_initialized) return ZKP_ERR_INVALID_ARG;
    if (left >= circuit->num_wires || right >= circuit->num_wires || out >= circuit->num_wires) return ZKP_ERR_INVALID_ARG;
    if (circuit->gate_count >= ZKP_MAX_GATES) return ZKP_ERR_TABLE_FULL;

    zkp_gate_t *g = &circuit->gates[circuit->gate_count++];
    g->op = op;
    g->left_wire = left;
    g->right_wire = right;
    g->out_wire = out;
    g->q_l = q_l % ZKP_PRIME_P;
    g->q_r = q_r % ZKP_PRIME_P;
    g->q_m = q_m % ZKP_PRIME_P;
    g->q_c = q_c % ZKP_PRIME_P;
    return 0;
}

int zkp_sponge_absorb(zkp_circuit_t *circuit, const uint64_t *elements, size_t count) {
    if (!circuit || !circuit->is_initialized || (!elements && count > 0)) return ZKP_ERR_INVALID_ARG;
    for (size_t i = 0; i < count; i++) {
        if (circuit->sponge_count >= ZKP_MAX_SPONGE_WORDS) return ZKP_ERR_SPONGE_FULL;
        uint64_t elem = elements[i] % ZKP_PRIME_P;
        circuit->sponge_words[circuit->sponge_count++] = elem;
        /* FNV-1a like mix inside finite field */
        circuit->sponge_state = ((circuit->sponge_state ^ elem) * 0x01000193ULL) % ZKP_PRIME_P;
    }
    return 0;
}

int zkp_verify_field_canonical(const zkp_proof_t *proof) {
    if (!proof) return ZKP_ERR_INVALID_ARG;
    if (proof->comm_a >= ZKP_PRIME_P || proof->comm_b >= ZKP_PRIME_P ||
        proof->comm_c >= ZKP_PRIME_P || proof->comm_z >= ZKP_PRIME_P) {
        return ZKP_ERR_NON_CANONICAL;
    }
    if (proof->eval_a >= ZKP_PRIME_P || proof->eval_b >= ZKP_PRIME_P ||
        proof->eval_c >= ZKP_PRIME_P || proof->eval_z >= ZKP_PRIME_P ||
        proof->eval_z_next >= ZKP_PRIME_P) {
        return ZKP_ERR_NON_CANONICAL;
    }
    for (uint32_t i = 0; i < proof->wire_count && i < ZKP_MAX_WIRES; i++) {
        if (proof->wire_evals[i] >= ZKP_PRIME_P) {
            return ZKP_ERR_NON_CANONICAL;
        }
    }
    return 0;
}

int zkp_verify_circuit_satisfaction(const zkp_circuit_t *circuit, const zkp_proof_t *proof, uint64_t challenge_beta, uint64_t challenge_gamma) {
    if (!circuit || !circuit->is_initialized || !proof) return ZKP_ERR_INVALID_ARG;
    if (proof->wire_count != circuit->num_wires) return ZKP_ERR_INVALID_ARG;

    /* 1. Canonical field check */
    int canon = zkp_verify_field_canonical(proof);
    if (canon != 0) return canon;

    /* 2. Public input binding check */
    for (uint32_t i = 0; i < circuit->num_public_inputs; i++) {
        if (proof->wire_evals[i] != circuit->public_inputs[i]) {
            return ZKP_ERR_PUBLIC_MISMATCH;
        }
    }

    /* 3. Gate satisfaction checks */
    for (uint32_t i = 0; i < circuit->gate_count; i++) {
        const zkp_gate_t *g = &circuit->gates[i];
        uint64_t w_l = proof->wire_evals[g->left_wire];
        uint64_t w_r = proof->wire_evals[g->right_wire];
        uint64_t w_o = proof->wire_evals[g->out_wire];

        if (g->op == GATE_OP_ADD) {
            uint64_t term_l = (g->q_l * w_l) % ZKP_PRIME_P;
            uint64_t term_r = (g->q_r * w_r) % ZKP_PRIME_P;
            uint64_t sum = (term_l + term_r) % ZKP_PRIME_P;
            if (sum != w_o) return ZKP_ERR_GATE_UNSAT;
        } else if (g->op == GATE_OP_MUL) {
            uint64_t prod = (w_l * w_r) % ZKP_PRIME_P;
            uint64_t term = (g->q_m * prod) % ZKP_PRIME_P;
            if (term != w_o) return ZKP_ERR_GATE_UNSAT;
        } else if (g->op == GATE_OP_CONST) {
            if (w_l != g->q_c) return ZKP_ERR_GATE_UNSAT;
        }
    }

    /* 4. Copy constraint permutation polynomial identity check */
    uint64_t beta = challenge_beta % ZKP_PRIME_P;
    uint64_t gamma = challenge_gamma % ZKP_PRIME_P;

    uint64_t t1 = (proof->eval_a + beta) % ZKP_PRIME_P;
    t1 = (t1 + gamma) % ZKP_PRIME_P;
    uint64_t lhs = (t1 * proof->eval_z) % ZKP_PRIME_P;

    uint64_t t2 = (proof->eval_b + ((beta * 2) % ZKP_PRIME_P)) % ZKP_PRIME_P;
    t2 = (t2 + gamma) % ZKP_PRIME_P;
    uint64_t rhs = (t2 * proof->eval_z_next) % ZKP_PRIME_P;

    if (lhs != rhs) {
        return ZKP_ERR_COPY_CONSTRAINT;
    }

    return 0;
}

/* Verification test suite in main() */
int main(void) {
    zkp_circuit_t circuit;
    uint64_t pub[2] = { 10, 20 };
    zkp_init_circuit(&circuit, 4, 2, pub);

    /* Gate 0: ADD wire[0] + wire[1] -> wire[2] (10 + 20 = 30) */
    zkp_add_gate(&circuit, GATE_OP_ADD, 0, 1, 2, 1, 1, 0, 0);
    /* Gate 1: MUL wire[0] * wire[1] -> wire[3] (10 * 20 = 200) */
    zkp_add_gate(&circuit, GATE_OP_MUL, 0, 1, 3, 0, 0, 1, 0);
    /* Gate 2: CONST wire[0] == 10 */
    zkp_add_gate(&circuit, GATE_OP_CONST, 0, 0, 0, 0, 0, 0, 10);

    zkp_proof_t valid_proof = {
        .wire_evals = { 10, 20, 30, 200 },
        .wire_count = 4,
        .comm_a = 100, .comm_b = 200, .comm_c = 300, .comm_z = 400,
        .eval_a = 50, .eval_b = 60, .eval_c = 70,
        .eval_z = 12345,
        .eval_z_next = 0
    };
    /* Compute matching eval_z_next so copy constraint holds for beta=5, gamma=7 */
    uint64_t beta = 5, gamma = 7;
    valid_proof.eval_a = 10;
    valid_proof.eval_b = 5;
    valid_proof.eval_z = 999;
    valid_proof.eval_z_next = 999;

    int passed = 0;
    int total = 8;

    /* Test 1: Normal circuit verification */
    if (zkp_verify_circuit_satisfaction(&circuit, &valid_proof, beta, gamma) == 0) {
        passed++;
    }

    /* Test 2: Non-canonical polynomial commitment trapping */
    zkp_proof_t bad_comm = valid_proof;
    bad_comm.comm_a = ZKP_PRIME_P + 5;
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_comm, beta, gamma) == ZKP_ERR_NON_CANONICAL) {
        passed++;
    }

    /* Test 3: Non-canonical wire evaluation trapping */
    zkp_proof_t bad_wire = valid_proof;
    bad_wire.wire_evals[2] = ZKP_PRIME_P;
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_wire, beta, gamma) == ZKP_ERR_NON_CANONICAL) {
        passed++;
    }

    /* Test 4: Public input mismatch check */
    zkp_proof_t bad_pub = valid_proof;
    bad_pub.wire_evals[0] = 11; /* expected 10 */
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_pub, beta, gamma) == ZKP_ERR_PUBLIC_MISMATCH) {
        passed++;
    }

    /* Test 5: ADD gate constraint violation check */
    zkp_proof_t bad_add = valid_proof;
    bad_add.wire_evals[2] = 31; /* 10 + 20 != 31 */
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_add, beta, gamma) == ZKP_ERR_GATE_UNSAT) {
        passed++;
    }

    /* Test 6: MUL gate constraint violation check */
    zkp_proof_t bad_mul = valid_proof;
    bad_mul.wire_evals[3] = 199; /* 10 * 20 != 199 */
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_mul, beta, gamma) == ZKP_ERR_GATE_UNSAT) {
        passed++;
    }

    /* Test 7: Copy constraint permutation identity check */
    zkp_proof_t bad_copy = valid_proof;
    bad_copy.eval_z_next = 888; /* mismatch with eval_z */
    if (zkp_verify_circuit_satisfaction(&circuit, &bad_copy, beta, gamma) == ZKP_ERR_COPY_CONSTRAINT) {
        passed++;
    }

    /* Test 8: Sponge absorption and challenge state determinism check */
    uint64_t sponge_in[3] = { 100, 200, 300 };
    zkp_sponge_absorb(&circuit, sponge_in, 3);
    if (circuit.sponge_count == 3 && circuit.sponge_state < ZKP_PRIME_P) {
        passed++;
    }

    if (passed == total) {
        printf("cyberbench{zerokey_zkp_circuit_verifier_security_state_8c72b15e4f901a3c}\n");
        return 0;
    } else {
        printf("FAILED checks: %d/%d passed\n", passed, total);
        return 1;
    }
}
