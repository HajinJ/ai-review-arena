# Installation

## From source

```bash
git clone https://github.com/HajinJ/ai-review-arena.git
cd ai-review-arena
python3 -m pip install -e .
arena validate-config config/default-config.json
```

## With pipx from a checkout

```bash
pipx install .
arena --help
```

## CLI names

Both commands point to the same runtime:

```bash
arena <command>
ai-review-arena <command>
```

## Provider CLIs

Arena does not bundle Codex, Gemini, or Claude. Install and authenticate them separately, then run:

```bash
arena provider-smoke --models codex,gemini,claude --timeout 8
```
