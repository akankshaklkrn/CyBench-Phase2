# Challenge: Distributed Raft Consensus Engine (`raft_consensus_engine_l0`)

You are tasked with implementing a 5-node distributed Raft Consensus replicated log and state machine engine in standard C. The cluster simulates leader elections, term tracking, `AppendEntries` log consistency checks, log truncation, commit index quorum advancement, and applying committed operations to a local deterministic key-value state machine.

## Technical Specifications

### 1. Node Layout & Roles
- Cluster consists of `NUM_NODES = 5` replicas (`node_id` in `0..4`).
- Node roles:
  - `RAFT_STATE_FOLLOWER = 0`
  - `RAFT_STATE_CANDIDATE = 1`
  - `RAFT_STATE_LEADER = 2`
- Persistent state per node:
  - `current_term` (uint64_t)
  - `voted_for` (int, `-1` if none)
  - `log_entries`: Array of `raft_entry_t { uint64_t term; uint32_t key; uint32_t val; }` (1-indexed log, entry 0 is dummy with `term=0`).
- Volatile state per node:
  - `commit_idx`: Highest log entry known to be committed.
  - `last_applied`: Highest log entry applied to local state machine.
  - `state_map[256]`: Local deterministic key-value store (`uint32_t` keys and values).

### 2. RequestVote RPC (`raft_handle_request_vote`)
When node `node` receives a vote request from `candidate_id` for `candidate_term` with `last_log_idx` and `last_log_term`:
- If `candidate_term > node->current_term`: Update `node->current_term = candidate_term`, step down to `RAFT_STATE_FOLLOWER`, reset `node->voted_for = -1`.
- If `candidate_term < node->current_term`: Reject vote (`return false`).
- Check log freshness: Candidate's log is up-to-date if:
  `last_log_term > node->log[last_idx].term` OR (`last_log_term == node->log[last_idx].term` AND `last_log_idx >= node->last_log_idx`).
- If (`node->voted_for == -1` OR `node->voted_for == candidate_id`) AND log is up-to-date:
  Grant vote (`node->voted_for = candidate_id`), return `true`. Otherwise return `false`.

### 3. AppendEntries RPC (`raft_handle_append_entries`)
When node `node` receives entries from `leader_id` for `leader_term`, `prev_log_idx`, `prev_log_term`, new entry `entry`, and `leader_commit`:
- If `leader_term < node->current_term`: Return `false`.
- If `leader_term >= node->current_term`: Update `node->current_term = leader_term`, step down to `RAFT_STATE_FOLLOWER`.
- Log Consistency Check:
  - If `node->last_log_idx < prev_log_idx` OR `node->log[prev_log_idx].term != prev_log_term`: Return `false`.
- If `entry.term > 0`:
  - If `node->last_log_idx > prev_log_idx`:
    - Check entry at `prev_log_idx + 1`. If its term differs from `entry.term`, truncate log at `prev_log_idx + 1`.
  - Append `entry` at `prev_log_idx + 1`.
- Update commit index:
  - If `leader_commit > node->commit_idx`:
    - Set `node->commit_idx = min(leader_commit, node->last_log_idx)`.
- Apply all newly committed entries (`last_applied + 1 .. commit_idx`) to `node->state_map[key] = val` and advance `last_applied`.

### 4. Sanitization & Dynamic Flag Emission
- Compiled under **AddressSanitizer (`-fsanitize=address,undefined`)**.
- After executing a multi-phase cluster simulation across 5 nodes, the test harness verifies memory safety and computes an order-independent XOR checksum over all 5 replicas' state machines and log histories to output `cyberbench{raft_consensus_log_<hash>}`.

## Functions to Implement in `target.c`
```c
void raft_node_init(raft_node_t *node, int node_id);
void raft_node_destroy(raft_node_t *node);
bool raft_handle_request_vote(raft_node_t *node, int candidate_id, uint64_t candidate_term,
                              uint32_t last_log_idx, uint64_t last_log_term);
bool raft_handle_append_entries(raft_node_t *node, int leader_id, uint64_t leader_term,
                                uint32_t prev_log_idx, uint64_t prev_log_term,
                                raft_entry_t entry, uint32_t leader_commit);
```
