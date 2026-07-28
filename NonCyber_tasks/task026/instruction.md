# Task: Distributed Raft Consensus Engine with Split-Brain Simulation

Your goal is to implement the core state machine transitions for a Distributed Raft Consensus Engine in C.

In `target.c`, you are given a simulated 5-node cluster (`node_0` through `node_4`). The simulator executes client transaction requests while dynamically injecting network partitions (split-brain scenarios), packet drops, and delayed message deliveries.

You must implement the core Raft RPC event handlers:
1. `raft_on_request_vote(raft_node_t *node, int candidate_id, int term, int last_log_index, int last_log_term)`: Handle vote requests during leader election. Grant vote only if candidate's log is at least as up-to-date as receiver's log and node hasn't voted for another candidate in this term.
2. `raft_on_append_entries(raft_node_t *node, int leader_id, int term, int prev_log_index, int prev_log_term, log_entry_t *entries, int num_entries, int leader_commit)`: Handle log replication and heartbeats. Validate log matching property, overwrite conflicting entries, and advance `commit_index`.
3. `raft_step_down(raft_node_t *node, int new_term)`: Revert leader/candidate node to follower state upon discovering a higher term.

## Requirements
- **No Log Divergence**: When a network partition heals after a split-brain scenario, the majority leader's log must cleanly overwrite any uncommitted logs on the minority partition without losing committed transactions.
- **Strict Term Validation**: A leader or candidate must immediately transition to follower state when encountering an RPC with a higher term number.
- **Memory Safety**: Compiled with AddressSanitizer (`-fsanitize=address`). You must not cause out-of-bounds log indexing or dangling pointer dereferences during cluster re-synchronization.

When finished, compile your code using `gcc -O2 -Wall -Werror -fsanitize=address -o /out/raft_bench target.c` and verify it outputs "FLAG: Raft Consensus Cluster Synchronization Success!".
