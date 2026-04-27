# Troubleshooting

## Provider binary exists but live benchmark skips

Run:

```bash
arena provider-smoke --models codex,gemini,claude --timeout 8
```

If the status is `auth_required`, login to the provider CLI. If it is `interactive_prompt`, configure the CLI for non-interactive mode. If it is `preflight_timeout`, increase timeout or inspect provider network/auth state.

## OTel collector smoke fails

Check Docker availability and port `4318`:

```bash
docker ps
bash tests/integration/test-otel-collector.sh
```

## MCP tool blocked

Inspect these config keys:

- `mcp.allowed_tools`
- `mcp.security.allowed_commands`
- `mcp.security.allowed_cwd_roots`
- `mcp.side_effect_tools`

## RAG returns weak evidence

Rebuild the index and enable semantic scoring:

```bash
arena rag-indexer . --force --config config/default-config.json
arena rag-evidence . security "token validation" --config config/default-config.json --top-k 5
```
