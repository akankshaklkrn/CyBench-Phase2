# CyberBench Pilot Five

Five diverse Harbor / Terminal-Bench-compatible task packages:

1. `mqtt-retained-shadow` - stateful MQTT retained-message and reconciler chain.
2. `iam-boundary-tag-cycle` - cloud IAM boundary, session tag, and resource-policy chain.
3. `sqlite-wal-schema-drift` - forensic WAL reconstruction with schema drift and a forged frame.
4. `ebpf-tailcall-maze` - eBPF-like binary container, tail calls, and ARX constraint recovery.
5. `federated-mask-dropout` - modular linear recovery from reused secure-aggregation masks.

Run one task with:

```bash
harbor run --path final_tasks/<task> --agent oracle --force-build
harbor run --path final_tasks/<task> --agent terminus-2 \
  --model openrouter/google/gemini-3.1-pro-preview
```

Docker/Harbor were unavailable in the construction workspace. `VALIDATION.md` distinguishes
completed local logic checks from the required Harbor-host checks.
