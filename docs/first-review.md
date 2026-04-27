# First Review in 5 Minutes

1. Install Arena:

```bash
python3 -m pip install -e .
```

2. Validate configuration:

```bash
arena validate-config config/default-config.json
```

3. Build a RAG index:

```bash
arena rag-indexer . --config config/default-config.json
```

4. Check provider readiness:

```bash
arena provider-smoke --models codex,gemini,claude --timeout 30
```

5. Run deterministic harness checks:

```bash
arena retrieval-benchmark --config config/default-config.json --max-cases 3
arena benchmark-harness-ablation --config config/default-config.json --max-cases 3
```

6. Run a bounded live smoke only after providers report `non_interactive_ready: true`:

```bash
arena benchmark-models --category security --models codex,gemini --live --smoke --timeout 90 --preflight-timeout 30 --require-live-success
```
