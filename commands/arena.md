---
description: "Run AI Review Arena through the typed runtime"
argument-hint: "[scope] [--phase all|review|stack|research] [--intensity quick|standard|deep|comprehensive]"
allowed-tools: [Bash]
---

# AI Review Arena

This command no longer contains the executable pipeline. The runtime source of truth is `config/runtime-pipeline.json`, executed by `arena_runtime.orchestrator`.

Run the typed hook/runtime entrypoint instead of interpreting a Markdown phase plan:

```bash
python3 scripts/arena-runtime.py hook-post-tool-use --project-root "$(pwd)" --config config/default-config.json
```

For non-hook orchestration, add functionality to `arena_runtime/` first, then expose it here as a thin command wrapper.
