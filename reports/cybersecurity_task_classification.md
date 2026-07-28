# CyBench Phase 2: Cybersecurity Task Classification

## Classification rule

A task is classified as **cybersecurity** when its primary objective is to protect
systems or data from adversarial actions, find or exploit vulnerabilities, analyze
malicious activity, enforce a security boundary, or implement/verify a security or
cryptographic control. This includes offensive security, defensive security,
forensics, IAM, cryptography, privacy-preserving security, trusted computing, and
secure sandboxing.

A task is classified as **non-cybersecurity** when its primary objective is ordinary
algorithm, database, concurrency, memory-management, compiler/runtime, networking,
or operating-system engineering—even if the prompt uses words such as
"vulnerability," uses a sanitizer, or requires memory-safe/correct behavior.

## Cross-check of the proposed non-cybersecurity list

All 26 proposed tasks are correctly classified as non-cybersecurity:

`task005`, `task007`, `task008`, `task009`, `task010`, `task011`, `task012`,
`task013`, `task014`, `task016`, `task018`, `task019`, `task020`, `task021`,
`task022`, `task024`, `task026`, `task027`, `task029`, `task030`, `task031`,
`task033`, `task035`, `task036`, `task038`, `task042`.

## Complete non-cybersecurity list (35)

- `task001` — lock-free stack ABA/concurrency correctness
- `task003` — graph-based network single-point-of-failure analysis
- `task005` — 4D geofencing/range-query database
- `task007` — virtual-machine opcode implementation
- `task008` — garbage collector implementation
- `task009` — B-tree implementation
- `task010` — custom memory allocator
- `task011` — red-black tree implementation
- `task012` — AVL tree implementation
- `task013` — B+ tree implementation
- `task014` — lock-free queue implementation
- `task015` — JSON parser and memory-management correctness
- `task016` — splay tree implementation
- `task017` — lock-free stack with hazard pointers
- `task018` — radix tree implementation
- `task019` — lock-free skip list
- `task020` — treap implementation
- `task021` — concurrent ring buffer
- `task022` — concurrent LLRB tree
- `task023` — hazard-pointer memory reclamation
- `task024` — database WAL crash recovery
- `task025` — x86-64 JIT compiler
- `task026` — Raft consensus
- `task027` — buddy memory allocator
- `task029` — LSM-tree storage engine
- `task030` — adaptive radix tree
- `task031` — concurrent cuckoo hash table
- `task032` — user-space network packet pipeline
- `task033` — MVCC storage engine
- `task034` — virtual-memory paging and TLB engine
- `task035` — Raft consensus engine
- `task036` — concurrent B-tree engine
- `task038` — relational query execution engine
- `task041` — hypervisor shadow MMU/TLB virtualization
- `task042` — MVCC and snapshot-isolation engine

## Complete cybersecurity list (42)

- `task002` — authenticated Path ORAM
- `task004` — AES-128 cryptography
- `task006` — heap exploitation/tcache poisoning
- `task028` — post-quantum Ring-LWE cryptography
- `task037` — eBPF safety verifier
- `task039` — WebAssembly sandbox and bounds enforcement
- `task040` — eBPF verifier preventing unsafe kernel memory access
- `task043` — TLS 1.3 handshake and record security
- `task044` — kernel eBPF safety/bounds verifier
- `task045` — TEE enclave memory and attestation
- `task046` — hardened secure heap allocator
- `task047` — sandboxed WebAssembly JIT security
- `task048` — OAuth2/OIDC/JWT security
- `task049` — stateful firewall/connection tracking
- `task050` — zero-knowledge proof verification
- `task051` — SGX enclave pointer-boundary security
- `task052` — PQC key exchange/signature verification
- `task053` — SAML SSO/XML signature security
- `task054` — prompt-injection/tool-call security firewall
- `task055` — FHE noise-budget security verification
- `task056` — SPIFFE/SPIRE workload identity and attestation
- `task057` — post-quantum KEM CCA-security simulator
- `task058` — eBPF verifier and Spectre mitigation
- `task059` — TDX attestation validation
- `task060` — zk-SNARK verification
- `task061` — RSA timing side-channel attack
- `task062` — packet forensics and intrusion detection
- `task063` — X.509 certificate-chain validation
- `task064` — coupled cipher reversal and payload recovery
- `task065` — zk-SNARK R1CS verification/witness solving
- `task066` — differential power-analysis attack
- `task067` — post-quantum Module-LWE decryption
- `task068` — ROP exploit-payload synthesis
- `task069` — FHE/CKKS encrypted computation
- `task070` — verifiable-delay-function proof verification
- `task071` — robust threshold cryptography
- `task072` — enclave attestation measurement verification
- `task073` — CP-ABE cryptographic access control
- `task074` — differential-privacy budget enforcement
- `task075` — secure multi-party computation/garbled circuits
- `task076` — Bulletproofs proof verification
- `task077` — RSA cryptographic accumulator verification

## Additional non-cybersecurity tasks found

These nine tasks were not in the proposed list:

`task001`, `task003`, `task015`, `task017`, `task023`, `task025`, `task032`,
`task034`, `task041`.

## Borderline decisions

- `task003` is non-cybersecurity because the actual work is graph-based reliability
  and topology analysis. It has an availability/security use case, but it performs
  no adversarial analysis or security control.
- `task015`, `task017`, and `task023` concern memory safety, races, or use-after-free
  prevention, but their objectives are general parser/concurrency correctness rather
  than vulnerability discovery, exploitation, or security hardening.
- `task032` parses and routes packets, but it is network engineering rather than
  network security.
- `task039` is cybersecurity because linear-memory sandbox enforcement is an
  explicit security boundary, not merely interpreter correctness.
- `task041` is non-cybersecurity because its primary deliverable is an MMU/TLB
  virtualization engine; ordinary page-permission handling alone does not turn it
  into a security task.
- `task046` remains cybersecurity even though it is an allocator task, because its
  explicit purpose is adversarial heap hardening and mitigation of exploitation
  primitives.
- `task064` is cybersecurity because the task is framed as reversing a coupled
  cipher/compression scheme to recover an intercepted payload, rather than ordinary
  compression implementation.

