# Level 0 Challenge: Zero-Trust Linux Netlink & Stateful Firewall Connection Tracking Engine (`kernel_netlink_conntrack_security_l0`)

You are tasked with implementing a **Zero-Trust Stateful Connection Tracking & Netlink (`NFNETLINK`) IPC Verification Engine** inside a high-performance network security appliance. Stateful firewalls track active packet flows (`ct_entry_t`), manage expectation tables (`ct_expect_t`) for complex multi-connection protocols like FTP and SIP (`nf_conntrack_helper`), and process Netlink configuration messages (`nlattr_t`). Any vulnerability in Netlink attribute TLV parsing, helper type checking, sequence number validation, or expectation reference counting allows attackers to inject malformed rules, bypass firewall inspection, or corrupt conntrack state memory.

## System Specification

The conntrack verification engine (`conntrack_engine_t`) tracks active connections (`conns`), expectation entries (`expects`), and protocol helper bindings (`helpers`) across simulated network timestamps (`current_time`).

### 1. Engine & Conntrack Structures

```c
#define CT_MAX_CONNS 64
#define CT_MAX_EXPECTS 32
#define CT_MAX_HELPERS 8
#define NLA_ALIGNTO 4
#define NLA_ALIGN(len) (((len) + NLA_ALIGNTO - 1) & ~(NLA_ALIGNTO - 1))

typedef enum {
    CT_STATE_UNTRACKED = 0,
    CT_STATE_NEW = 1,
    CT_STATE_ESTABLISHED = 2,
    CT_STATE_EXPECTED = 3,
    CT_STATE_TIME_WAIT = 4,
    CT_STATE_DESTROYED = 5
} ct_state_t;

typedef enum {
    HELPER_NONE = 0,
    HELPER_FTP = 1,
    HELPER_SIP = 2
} helper_type_t;

typedef enum {
    TCP_FLAG_SYN = 0x01,
    TCP_FLAG_ACK = 0x02,
    TCP_FLAG_FIN = 0x04,
    TCP_FLAG_RST = 0x08
} tcp_flags_t;

typedef struct {
    uint32_t src_ip;
    uint32_t dst_ip;
    uint16_t src_port;
    uint16_t dst_port;
    uint8_t proto;
} ip_tuple_t;

typedef struct {
    uint16_t nla_len;
    uint16_t nla_type;
    uint8_t payload[0];
} nlattr_t;

typedef struct {
    uint32_t expect_id;
    uint32_t master_conn_id;
    ip_tuple_t tuple;
    helper_type_t helper;
    uint64_t expires_at;
    int refcnt;
    bool is_active;
} ct_expect_t;

typedef struct {
    uint32_t conn_id;
    ip_tuple_t orig_tuple;
    ip_tuple_t reply_tuple;
    ct_state_t state;
    helper_type_t helper;
    uint32_t last_seq;
    uint32_t last_ack;
    int refcnt;
    bool is_active;
} ct_entry_t;

typedef struct {
    uint16_t port;
    helper_type_t helper;
    bool is_active;
} ct_helper_bind_t;

typedef struct {
    ct_entry_t conns[CT_MAX_CONNS];
    ct_expect_t expects[CT_MAX_EXPECTS];
    ct_helper_bind_t helpers[CT_MAX_HELPERS];
    uint64_t current_time;
    uint32_t next_conn_id;
    uint32_t next_expect_id;
    bool is_initialized;
} conntrack_engine_t;
```

### 2. Core API Functions to Implement

You must complete the following five functions in `target.c`:

#### `void ct_init(conntrack_engine_t *engine, uint64_t now)`
Initializes the zero-trust conntrack engine:
- Sets `engine->is_initialized = true`, `engine->current_time = now`, `engine->next_conn_id = 1`, and `engine->next_expect_id = 100`.
- Zeroes out all tables (`conns`, `expects`, `helpers`).

#### `int ct_register_helper(conntrack_engine_t *engine, uint16_t port, helper_type_t helper)`
Registers a protocol helper binding on a target destination port:
- If `!engine || !engine->is_initialized || port == 0 || helper == HELPER_NONE`, return `-1` (`CT_ERR_INVALID_ARG`).
- Check if `port` is already registered with a *different* helper type (`engine->helpers[i].helper != helper`). If so, trap helper confusion and return `-4` (`CT_ERR_HELPER_CONFUSION`).
- Locate an existing matching slot or first inactive slot (`!is_active`) in `helpers[0..7]`, store `port` and `helper`, set `is_active = true`, and return `0`. If full, return `-5` (`CT_ERR_TABLE_FULL`).

#### `int ct_parse_nlmsg(const conntrack_engine_t *engine, const uint8_t *data, size_t len, nlattr_t **out_attrs, int max_attrs)`
Parses a Netlink attribute TLV buffer into `out_attrs` while strictly enforcing memory safety and alignment boundaries:
- If arguments invalid (`!engine || !engine->is_initialized || !data || !out_attrs || max_attrs <= 0`), return `-1`.
- Iterate through the buffer using `offset = 0` up to `max_attrs`:
  - Check whether remaining buffer length (`len - offset`) is at least `sizeof(uint32_t)` (header size for `nla_len` + `nla_type`). If not, return `-2` (`CT_ERR_NL_OVERFLOW`).
  - Read `nla_len = *(const uint16_t *)(data + offset)`. Check whether `nla_len < sizeof(uint32_t)` or `offset + nla_len > len`. If out of bounds or malformed length, return `-2` (`CT_ERR_NL_OVERFLOW`).
  - Compute `aligned_len = NLA_ALIGN(nla_len)`. If `aligned_len < nla_len`, return `-3` (`CT_ERR_NL_ALIGN`).
  - Store `(nlattr_t *)(data + offset)` in `out_attrs[count++]` and advance `offset += aligned_len`.
- Return the number of attributes successfully parsed (`count`).

#### `int ct_inject_expectation(conntrack_engine_t *engine, uint32_t master_id, const ip_tuple_t *expect_tuple, helper_type_t helper_type, uint64_t timeout_sec)`
Injects an expectation table entry for dynamic protocol openings (e.g., FTP passive data ports):
- If arguments invalid (`!engine || !engine->is_initialized || !expect_tuple || master_id == 0 || helper_type == HELPER_NONE`), return `-1`.
- Locate the active master connection matching `master_id` (`conns[i].conn_id == master_id`). If not found or master `state != CT_STATE_ESTABLISHED`, return `-6` (`CT_ERR_NOT_FOUND`).
- Verify helper type invariant: `master->helper` must equal `helper_type`. If mismatched (`e.g. master is FTP but injecting a SIP expectation`), immediately trap and return `-4` (`CT_ERR_HELPER_CONFUSION`).
- Locate first inactive slot in `expects[0..31]`, assign `expect_id = engine->next_expect_id++`, `master_conn_id = master_id`, `tuple = *expect_tuple`, `helper = helper_type`, `expires_at = engine->current_time + timeout_sec`, `refcnt = 1`, and `is_active = true`.
- Increment master connection reference count (`master->refcnt++`) and return `0`. If expectation table full, return `-5`.

#### `int ct_flush_expired(conntrack_engine_t *engine, uint64_t now)`
Evicts expired expectation entries and cleans up master references:
- If `!engine || !engine->is_initialized`, return `-1`.
- Update `engine->current_time = now`.
- Iterate through all active expectations (`expects[i].is_active`). For any entry where `engine->current_time >= exp->expires_at`:
  - Locate the corresponding master connection (`conn_id == exp->master_conn_id`). If found and `m->refcnt > 1`, decrement `m->refcnt--`.
  - Set `exp->is_active = false` and increment `flushed` count.
- Return `flushed`.

#### `int ct_process_packet(conntrack_engine_t *engine, const ip_tuple_t *tuple, uint32_t seq, uint32_t ack, uint32_t flags, ct_state_t *out_state)`
Processes a stateful packet against existing connections and expectation rules:
- If arguments invalid, return `-1`.
- **1. Check Existing Active Connections**:
  - Scan `conns[0..63]` for active entries matching either `orig_tuple` or `reply_tuple` (via `tuples_equal()`).
  - If match found on orig or reply tuple:
    - If packet contains `TCP_FLAG_FIN` or `TCP_FLAG_RST`, transition `conn->state = CT_STATE_TIME_WAIT`.
    - Else if `conn->state == CT_STATE_NEW` and packet has `TCP_FLAG_ACK`: check whether `ack == conn->last_seq + 1` (on orig match) or `ack == conn->last_seq + 1` (on reply match). If sequence number mismatch, return `-7` (`CT_ERR_SEQ_MISMATCH`). Otherwise transition `conn->state = CT_STATE_ESTABLISHED` and update `conn->last_ack = ack`.
    - Update `conn->last_seq = seq`. Set `*out_state = conn->state` and return `0`.
- **2. Check Expectation Table (`RELATED` Connections)**:
  - Scan `expects[0..31]` for active entries matching `tuple`.
  - If `engine->current_time >= exp->expires_at`, evict expired expectation (`exp->is_active = false`), decrement master `refcnt` (if `> 1`), and `continue` scanning.
  - If matching active expectation found (`tuples_equal(tuple, &exp->tuple)`):
    - Verify packet has `TCP_FLAG_SYN`. If `!(flags & TCP_FLAG_SYN)`, reject as sequence mismatch (`CT_ERR_SEQ_MISMATCH`).
    - Promote expectation into an active connection (`CT_STATE_EXPECTED`): find free slot in `conns`, set `conn_id = engine->next_conn_id++`, `orig_tuple = *tuple`, `reply_tuple` (inverting src/dst IPs and ports of `tuple`), `state = CT_STATE_EXPECTED`, `helper = exp->helper`, `last_seq = seq`, `refcnt = 1`, `is_active = true`.
    - Decrement master connection reference count (`m->refcnt--` if `> 1`), mark expectation `exp->is_active = false`, set `*out_state = CT_STATE_EXPECTED`, and return `0`.
- **3. Check New Connection (`NEW`)**:
  - If packet has `TCP_FLAG_SYN`, find free slot in `conns`, set `conn_id = engine->next_conn_id++`, `orig_tuple = *tuple`, `reply_tuple` (inverted tuple), `state = CT_STATE_NEW`, `last_seq = seq`, `refcnt = 1`, `is_active = true`.
  - If `tuple->dst_port` matches an active helper in `engine->helpers`, attach helper to `conn->helper`.
  - Set `*out_state = CT_STATE_NEW` and return `0`. If `conns` full, return `-5`.
- If no match and not `SYN`, return `-6` (`CT_ERR_NOT_FOUND`).

## Verification & Testing

Your implementation will be evaluated against a rigorous test suite (`main` in `target.c`) executing 8 complex zero-trust conntrack scenarios:
1. Normal connection creation (`NEW` -> `ESTABLISHED`) and sequence tracking.
2. Netlink attribute TLV length overflow & alignment vulnerability trapping.
3. Helper registration port confusion check (`CT_ERR_HELPER_CONFUSION`).
4. Protocol expectation injection and promotion to `CT_STATE_EXPECTED`.
5. Expectation sequence mismatch check (`TCP_FLAG_ACK` packet matching expected tuple without `SYN`).
6. Expectation helper mismatch trapping (`master->helper != helper_type`).
7. Expired expectation flush & reference count cleanup check (`ct_flush_expired`).
8. Handshake sequence number validation (`ack != last_seq + 1`).

When all zero-trust checks pass without memory errors, the driver prints:
```
cyberbench{kernel_netlink_conntrack_security_state_9a4f2108bc77e3d1}
```
