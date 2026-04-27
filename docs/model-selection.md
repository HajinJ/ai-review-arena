# Model Selection Policy

Last updated: 2026-04-27

AI Review Arena should not force a frontier model by default. Users already configure preferred models in Claude Code, Codex, and Gemini. The plugin should respect those defaults unless the user or project explicitly opts into an override.

## Default behavior

- Claude reviewer agents should inherit the user's active Claude Code model unless a specific agent role intentionally pins a model.
- Codex wrappers should not pass `-m` when `models.codex.use_user_default` is `true`.
- Gemini wrappers should not pass `--model` when `models.gemini.use_user_default` is `true`.
- `.codex/config.toml` intentionally omits a `model` key so it does not override the user's Codex default.
- `.codex/agents/*.toml` intentionally omit `model` keys so Codex subagents inherit the active Codex default.

## Explicit override behavior

To force a model for repeatable benchmark or CI runs:

```json
{
  "models": {
    "codex": {
      "use_user_default": false,
      "model_variant": "gpt-5.5"
    },
    "gemini": {
      "use_user_default": false,
      "model_variant": "gemini-3.1-pro-preview"
    }
  }
}
```

Recommended explicit override baselines:

- Codex high-capability review: `gpt-5.5`
- Codex cost-sensitive review: `gpt-5.4-mini`
- Gemini review: `gemini-3.1-pro-preview` or a newer Gemini 3.1 successor
- Claude review profile: `claude-opus-4-7` for strongest review, `claude-sonnet-4-6` for balanced review

## Deprecated model rule

Do not reintroduce `gemini-3-pro-preview`. It has been removed from defaults because it is no longer a safe baseline.

## Benchmarking rule

Benchmarks should pin model IDs for reproducibility. Interactive user flows should inherit user defaults.
