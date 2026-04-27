# Dashboard

Build a static dashboard from harness events and benchmark JSON:

```bash
arena retrieval-benchmark --config config/default-config.json --max-cases 3 > retrieval.json
arena benchmark-harness-ablation --config config/default-config.json --max-cases 3 > ablation.json
arena dashboard-build --runs-dir cache/runs --benchmark-json retrieval.json --benchmark-json ablation.json --output cache/dashboard/index.html
```

The dashboard writes:

- `cache/dashboard/index.html`
- `cache/dashboard/summary.json`

Nightly dogfooding uploads this directory as a GitHub Actions artifact.
