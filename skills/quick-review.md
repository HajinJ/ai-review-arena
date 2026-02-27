---
name: quick-review
description: Quick single-file code review using Arena pipeline
arguments:
  - name: file
    description: File path to review
    required: false
---

# Quick Review

Perform a quick code review on the specified file or current file.

## Instructions

1. Identify the target file (argument or ask user)
2. Read the file content
3. Analyze for: security issues, bugs, performance problems, code style
4. Present findings in a concise format with severity levels
5. Keep it lightweight — no external CLI calls, no debate rounds
