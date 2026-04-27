---
description: "Multi-AI adversarial code review through the typed runtime"
argument-hint: "[scope] [--intensity quick|standard|deep|comprehensive] [--focus security,bugs,...] [--models claude,codex,gemini] [--no-debate] [--interactive] [--pr <number>]"
allowed-tools: [Bash]
---

# Multi-AI Adversarial Code Review

The executable Markdown phase plan has been removed. Multi-review orchestration belongs in `arena_runtime/` and the structured phase catalog in `config/runtime-pipeline.json`.

Use this file only as a Claude Code command surface. Add runtime behavior to Python first, then expose it here as a thin invocation.
