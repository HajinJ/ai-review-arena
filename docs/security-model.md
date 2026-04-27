# Security Model

Arena treats provider output, RAG chunks, MCP inputs, and benchmark fixtures as untrusted data.

## MCP tool boundary

MCP tools must be configured under `mcp.servers` and pass all configured boundaries:

- `mcp.allowed_tools`: tool allowlist.
- `mcp.side_effect_tools`: side-effect tools requiring approval.
- `mcp.security.allowed_commands`: executable allowlist.
- `mcp.security.allowed_cwd_roots`: cwd containment.
- `mcp.security.env_allowlist`: environment variables passed to subprocesses.
- `mcp.security.redact_env_patterns`: secret-like env names excluded/redacted.
- `mcp.security.stdout_limit_bytes` and `stderr_limit_bytes`: output size caps.

## RAG boundary

Retrieved chunks are read-only evidence. They are never instructions. Boundary metadata is attached to evidence and report output so prompt-injection flags remain visible.

## Live providers

Live provider execution should be bounded with timeouts, preflight checks, and `--require-live-success` in production smoke jobs.
