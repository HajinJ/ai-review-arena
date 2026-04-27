#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

python3 - <<'PY'
import json
import os
import tempfile
from pathlib import Path

from arena_runtime.autofix import AutoFixPolicy, prepare_isolated_patch
from arena_runtime.evaluation import Finding, GroundTruth, SeverityCalibrator, score_findings
from arena_runtime.observability import TraceLogger
from arena_runtime.policy import ApprovalDecision, RuntimePolicy, ToolRequest
from arena_runtime.providers import ModelSelection, parse_command, provider_model_args
from arena_runtime.schemas import normalize_provider_payload

# Model inheritance: user defaults must not emit model flags.
assert provider_model_args("codex", ModelSelection(use_user_default=True, model_variant="gpt-5.5")) == []
assert provider_model_args("gemini", ModelSelection(use_user_default=True, model_variant="gemini-3.1-pro-preview")) == []
assert provider_model_args("codex", ModelSelection(use_user_default=False, model_variant="gpt-5.5")) == ["-m", "gpt-5.5"]
assert provider_model_args("gemini", ModelSelection(use_user_default=False, model_variant="gemini-3.1-pro-preview")) == ["--model", "gemini-3.1-pro-preview"]
assert parse_command("codex exec") == ["codex", "exec"]

# Runtime policy: read-only tools pass; side effects require explicit approval and allowed credentials.
policy = RuntimePolicy(allowed_tools={"read_file", "write_file"}, side_effect_tools={"write_file"}, credential_scopes={"github": {"GITHUB_TOKEN"}}, allowed_commands={"codex"})
assert policy.authorize_tool(ToolRequest(name="read_file", side_effect=False)).allowed
assert not policy.authorize_tool(ToolRequest(name="write_file", side_effect=True)).allowed
assert policy.authorize_tool(ToolRequest(name="write_file", side_effect=True, approval=ApprovalDecision(approved=True, approver="user"))).allowed
assert not policy.authorize_credentials("github", {}).allowed
assert policy.authorize_credentials("github", {"GITHUB_TOKEN": "set"}).allowed
assert policy.authorize_command(["codex", "exec"]).allowed
assert not policy.authorize_command(["curl", "https://example.com"]).allowed

# Provider output validation normalizes CLI JSON before aggregation.
payload, issues = normalize_provider_payload({"model": "codex", "role": "bugs", "file": "app.py", "findings": [{"title": "Bug", "line": "7", "confidence": 120}]})
assert not issues
assert payload["findings"][0]["line"] == 7
assert payload["findings"][0]["confidence"] == 100
_, issues = normalize_provider_payload({"findings": [{"line": 1}]})
assert issues[0].path == "$.findings[0].title"

# Line-level evaluation and severity calibration.
findings = [Finding(file="src/auth.py", line=42, severity="high", title="SQL injection", confidence=80)]
truth = [GroundTruth(file="src/auth.py", line=43, severity="critical", title="SQL injection")]
score = score_findings(findings, truth, line_tolerance=2)
assert score.true_positives == 1
assert score.false_positives == 0
assert score.false_negatives == 0
assert round(score.precision, 3) == 1.0
assert SeverityCalibrator().calibrate("critical", 72) > SeverityCalibrator().calibrate("low", 72)

# Observability writes structured JSONL.
with tempfile.TemporaryDirectory() as td:
    trace = TraceLogger(Path(td) / "trace.jsonl")
    trace.record("model_call", provider="codex", model="user-default", cost_usd=0.01)
    trace.record_cli_call(provider="codex", command=["codex", "exec"], model="user-default", exit_code=0, latency_ms=10, stdout_bytes=12, stderr_bytes=0, timed_out=False, structured_output=True, schema_requested=True)
    rows = [json.loads(line) for line in (Path(td) / "trace.jsonl").read_text().splitlines()]
    assert rows[0]["event"] == "model_call"
    assert rows[0]["provider"] == "codex"
    assert "ts" in rows[0]
    assert rows[1]["event"] == "cli_call"
    assert rows[1]["exit_code"] == 0

# Auto-fix isolation creates a patch artifact without applying production edits.
with tempfile.TemporaryDirectory() as td:
    target = Path(td) / "app.py"
    target.write_text("print('old')\n")
    patch = prepare_isolated_patch(target, "print('new')\n", AutoFixPolicy(enabled=True, require_human_approval=True), approved=False)
    assert not patch.allowed
    assert target.read_text() == "print('old')\n"
    patch = prepare_isolated_patch(target, "print('new')\n", AutoFixPolicy(enabled=True, require_human_approval=True), approved=True)
    assert patch.allowed
    assert patch.patch_path.exists()
    assert target.read_text() == "print('old')\n"

print("arena_runtime unit checks passed")
PY
