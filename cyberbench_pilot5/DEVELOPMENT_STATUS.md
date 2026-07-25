# Development Snapshot Status

This is an in-progress snapshot, not a Harbor-validated release.

## Present task directories

- `iam-boundary-tag-cycle`
- `mqtt-retained-shadow`
- `sqlite-wal-schema-drift`
- `ebpf-tailcall-maze`
- `federated-mask-dropout`

Each directory contains a Harbor-style manifest, instructions, environment, oracle solution,
and deterministic verifier draft. Static artifacts and both synthetic network services are present.

## Known blocking defects

- Generated oracle shell wrappers need indentation and here-document escaping cleanup.
- The eBPF runner currently fails Python compilation because of generator indentation.
- The revised federated system now has a full-rank design, but the regenerated oracle/verifier
  still needs execution validation.
- Docker and Harbor were unavailable in the construction workspace, so no image build or
  `harbor run --agent oracle` has been performed.

Do not submit this snapshot as a completed benchmark set. The included generator is the source
of truth for continuing development.
