# Provider Setup

Arena is CLI-first. Provider readiness means more than “binary exists”. A provider is ready only when it can run non-interactively and return review-shaped JSON.

```bash
arena provider-smoke --models codex,gemini,claude --timeout 30
```

Readiness statuses:

- `ready`: non-interactive JSON preflight completed.
- `auth_required`: login/API key/OAuth setup is missing.
- `interactive_prompt`: the CLI asked for confirmation or browser input.
- `preflight_timeout`: the CLI did not return within the timeout.
- `non_json_output`: the CLI ran but did not return review JSON.

Live benchmark guard:

```bash
arena benchmark-models --category security --models codex,gemini --live --smoke --require-live-success
```

Use `--require-live-success` in production smoke jobs so provider drift fails loudly instead of being silently skipped.
