from __future__ import annotations

import argparse
import json
import os
import shutil
import signal
import subprocess
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, Sequence

from .harness import HarnessRun
from .rag_runtime import attach_evidence_to_findings, format_evidence_for_prompt, retrieve_evidence
from .schemas import normalize_provider_payload

VALID_ROLES = {"security", "bugs", "performance", "architecture", "testing"}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_json(path: Path) -> Dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _model_cfg(cfg: Dict[str, Any], provider: str) -> Dict[str, Any]:
    models = cfg.get("models", {}) if isinstance(cfg.get("models"), dict) else {}
    return models.get(provider, {}) if isinstance(models.get(provider), dict) else {}


def _bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    return str(value).lower() in {"1", "true", "yes", "on"}


def _error(provider: str, role: str, message: str, exit_code: int = 0) -> int:
    print(json.dumps({"model": provider, "role": role, "error": message, "findings": []}, ensure_ascii=False))
    return exit_code


def _extract_json(text: str) -> Dict[str, Any] | None:
    stripped = text.strip()
    if not stripped:
        return None
    try:
        data = json.loads(stripped)
        return _coerce_json_payload(data) if isinstance(data, dict) else None
    except json.JSONDecodeError:
        pass
    decoder = json.JSONDecoder()
    for idx, char in enumerate(stripped):
        if char != "{":
            continue
        try:
            data, _ = decoder.raw_decode(stripped[idx:])
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            return _coerce_json_payload(data)
    return None


def _coerce_json_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    if isinstance(data.get("findings"), list):
        return data
    for key in ("response", "text", "content", "message", "output"):
        value = data.get(key)
        if isinstance(value, dict):
            nested = _coerce_json_payload(value)
            if isinstance(nested.get("findings"), list):
                return nested
        if isinstance(value, str):
            nested = _extract_json(value)
            if nested and isinstance(nested.get("findings"), list):
                return nested
    return data


def _prompt(role: str, file_path: str, content: str) -> str:
    prompt_file = _repo_root() / "config" / "review-prompts" / f"{role}.txt"
    template = prompt_file.read_text(encoding="utf-8") if prompt_file.exists() else f"Review for {role} issues."
    return f"{template}\n\n--- FILE: {file_path} ---\n{content}\n--- END FILE ---\n\nReview the code above for {role} issues in file {file_path}. Return valid JSON only with findings[]."


def _run(command: Sequence[str], prompt: str | None, timeout: int) -> subprocess.CompletedProcess[str]:
    cmd = list(command)
    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE if prompt is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        stdout, stderr = proc.communicate(input=prompt, timeout=max(1, timeout))
        return subprocess.CompletedProcess(cmd, proc.returncode, stdout, stderr)
    except subprocess.TimeoutExpired as exc:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
        try:
            stdout, stderr = proc.communicate(timeout=2)
        except Exception:
            stdout, stderr = exc.stdout or "", exc.stderr or ""
        return subprocess.CompletedProcess(cmd, 124, stdout or "", stderr or f"Timed out after {timeout}s")


def _provider_preflight_command(provider: str, prompt: str) -> tuple[list[str], str | None]:
    if provider == "codex":
        return (
            [
                "codex",
                "exec",
                "-c",
                'model_reasoning_effort="low"',
                "--skip-git-repo-check",
                "--ephemeral",
                "--ignore-rules",
                "--color",
                "never",
                "--sandbox",
                "read-only",
                "-",
            ],
            prompt,
        )
    if provider == "gemini":
        return (["gemini", "--output-format", "json", "--approval-mode", "plan", "--prompt", prompt], None)
    if provider == "claude":
        return (["claude", "-p", prompt, "--output-format", "json"], None)
    return ([], None)


def _classify_cli_result(provider: str, completed: subprocess.CompletedProcess[str], *, timeout: int, elapsed_ms: int) -> Dict[str, Any]:
    stdout = completed.stdout or ""
    stderr = completed.stderr or ""
    combined = f"{stdout}\n{stderr}".lower()
    status = "ready"
    reason = "non-interactive preflight completed"
    if completed.returncode == 124:
        status = "preflight_timeout"
        reason = f"{provider} preflight timed out after {timeout}s"
    elif any(marker in combined for marker in ["login", "not authenticated", "authentication", "api key", "oauth", "sign in"]):
        status = "auth_required"
        reason = f"{provider} requires authentication before non-interactive use"
    elif any(marker in combined for marker in ["press enter", "continue?", "confirm", "interactive", "browser"]):
        status = "interactive_prompt"
        reason = f"{provider} requested interactive input"
    elif completed.returncode not in {0, 1}:
        status = "preflight_error"
        reason = f"{provider} preflight exited with code {completed.returncode}"
    parsed = _extract_json(stdout)
    json_ready = bool(parsed is not None and isinstance(parsed.get("findings", []), list))
    if status == "ready" and not json_ready and stdout.strip():
        status = "non_json_output"
        reason = f"{provider} completed but did not emit review JSON"
    return {
        "status": status,
        "ready": status == "ready",
        "non_interactive_ready": status == "ready",
        "reason": reason,
        "exit_code": completed.returncode,
        "elapsed_cpu_ms": elapsed_ms,
        "stdout_bytes": len(stdout.encode()),
        "stderr_bytes": len(stderr.encode()),
        "json_ready": json_ready,
    }


def _normalize(provider: str, role: str, file_path: str, parsed: Dict[str, Any]) -> Dict[str, Any]:
    payload = {
        "model": provider,
        "role": role,
        "file": file_path,
        "findings": parsed.get("findings", []) if isinstance(parsed.get("findings"), list) else [],
        "summary": parsed.get("summary", "No summary provided"),
    }
    normalized, issues = normalize_provider_payload(payload)
    result = dict(normalized or payload)
    result["summary"] = payload["summary"]
    result["schema_status"] = "valid" if not issues else "normalized_with_issues"
    if issues:
        result["schema_issues"] = [issue.to_dict() for issue in issues]
    return result


def _version(command: str) -> Dict[str, Any]:
    if not shutil.which(command):
        return {"available": False, "version": ""}
    try:
        completed = subprocess.run([command, "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3, check=False)
    except Exception as exc:
        return {"available": True, "version": "", "error": str(exc)}
    text = (completed.stdout or completed.stderr or "").strip().splitlines()
    return {"available": True, "version": text[0] if text else "", "exit_code": completed.returncode}


def _diagnostic_preflight(provider: str, cfg: Dict[str, Any], timeout: int) -> Dict[str, Any]:
    prompt = 'Return exactly this JSON and no other text: {"findings":[],"summary":"ok"}'
    command, input_text = _provider_preflight_command(provider, prompt)
    if not command:
        return {"status": "unsupported"}
    started = time.monotonic()
    completed = _run(command, input_text, timeout)
    elapsed_ms = int((time.monotonic() - started) * 1000)
    return _classify_cli_result(provider, completed, timeout=timeout, elapsed_ms=elapsed_ms)


def cmd_cli_diagnostics(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="cli-diagnostics")
    parser.add_argument("--models", default="codex,gemini,claude")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--timeout", type=int, default=8)
    args = parser.parse_args(list(argv))

    cfg = _load_json(Path(args.config))
    providers = [item.strip() for item in args.models.split(",") if item.strip()]
    result: Dict[str, Any] = {"live": args.live, "timeout_seconds": args.timeout, "providers": {}}
    for provider in providers:
        provider_cfg = _model_cfg(cfg, provider)
        row: Dict[str, Any] = {
            **_version(provider),
            "use_user_default": _bool(provider_cfg.get("use_user_default"), True),
            "configured_model_variant": str(provider_cfg.get("model_variant") or ""),
            "recommended_model_variant": str(provider_cfg.get("recommended_model_variant") or provider_cfg.get("recommended_agent_model") or ""),
            "configured_timeout_seconds": int(provider_cfg.get("timeout_seconds", cfg.get("timeout", 120)) or 120),
        }
        if args.live and row.get("available"):
            row["preflight"] = _diagnostic_preflight(provider, cfg, max(1, args.timeout))
        result["providers"][provider] = row
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def cmd_provider_smoke(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="provider-smoke")
    parser.add_argument("--models", default="codex,gemini,claude")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--timeout", type=int, default=8)
    parser.add_argument("--require-ready", action="store_true")
    args = parser.parse_args(list(argv))

    cfg = _load_json(Path(args.config))
    providers = [item.strip() for item in args.models.split(",") if item.strip()]
    rows: Dict[str, Any] = {}
    ready_count = 0
    for provider in providers:
        version = _version(provider)
        row: Dict[str, Any] = {**version}
        if version.get("available"):
            preflight = _diagnostic_preflight(provider, cfg, max(1, args.timeout))
            row["preflight"] = preflight
            row["non_interactive_ready"] = bool(preflight.get("non_interactive_ready"))
            ready_count += 1 if row["non_interactive_ready"] else 0
        else:
            row["non_interactive_ready"] = False
            row["preflight"] = {"status": "unavailable", "reason": f"{provider} CLI unavailable"}
        rows[provider] = row
    output = {
        "status": "ready" if ready_count == len(providers) and providers else "partial",
        "ready_count": ready_count,
        "provider_count": len(providers),
        "providers": rows,
    }
    print(json.dumps(output, ensure_ascii=False, indent=2))
    if args.require_ready and ready_count < len(providers):
        return 2
    return 0


def cmd_review_provider(provider: str, argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog=f"{provider}-review")
    parser.add_argument("file_path")
    parser.add_argument("config_file")
    parser.add_argument("role")
    args = parser.parse_args(list(argv))
    if args.role not in VALID_ROLES:
        return _error(provider, args.role, f"Invalid role: {args.role}. Must be one of: {', '.join(sorted(VALID_ROLES))}", 1)
    if not shutil.which(provider):
        install = "npm install -g @openai/codex" if provider == "codex" else "npm install -g @google/gemini-cli"
        return _error(provider, args.role, f"{provider} CLI not found. Install: {install}", 1)
    cfg = _load_json(Path(args.config_file))
    project_root = Path(os.environ.get("ARENA_PROJECT_ROOT", os.getcwd())).resolve()
    harness = HarnessRun.from_env(project_root)
    harness.emit("review.started", phase="review", provider=provider, role=args.role, file=args.file_path)
    provider_cfg = _model_cfg(cfg, provider)
    timeout = int(provider_cfg.get("timeout_seconds", cfg.get("timeout", 120)) or 120)
    content = ""
    try:
        import sys

        content = sys.stdin.read()
    except Exception:
        content = ""
    if not content:
        return _error(provider, args.role, "No file content provided on stdin", 1)
    evidence = retrieve_evidence(project_root, args.role, f"{args.file_path}\n{content[:4000]}", args.config_file, preferred_file=args.file_path)
    harness.emit(
        "retrieval.completed",
        phase="retrieval",
        provider=provider,
        role=args.role,
        file=args.file_path,
        hit_count=len(evidence),
        evidence_ids=[item.get("id") for item in evidence],
    )
    full_prompt = _prompt(args.role, args.file_path, content) + format_evidence_for_prompt(evidence)
    root_cfg = cfg.get(provider, {}) if isinstance(cfg.get(provider), dict) else {}
    use_default = _bool(provider_cfg.get("use_user_default", root_cfg.get("use_user_default", True)), True)
    variant = str(provider_cfg.get("model_variant", root_cfg.get("model_variant", "")) or "")

    parsed: Dict[str, Any] | None = None
    error = ""
    if provider == "codex":
        base = ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "--ignore-rules", "--color", "never", "--sandbox", "read-only"]
        if not use_default and variant:
            base.extend(["-m", variant])
        structured = _bool(provider_cfg.get("structured_output", True), True)
        schema = _repo_root() / "config" / "schemas" / "codex-review.json"
        if structured and schema.exists():
            with tempfile.NamedTemporaryFile(delete=False) as out:
                output_path = Path(out.name)
            try:
                completed = _run([*base, "--output-schema", str(schema), "-o", str(output_path), "-"], full_prompt, timeout)
                if completed.returncode == 0 and output_path.exists():
                    parsed = _extract_json(output_path.read_text(encoding="utf-8"))
                elif completed.returncode == 124:
                    error = f"Codex review timed out after {timeout}s"
            finally:
                output_path.unlink(missing_ok=True)
        if parsed is None and not error:
            completed = _run([*base, "-"], full_prompt, timeout)
            if completed.returncode == 124:
                error = f"Codex review timed out after {timeout}s"
            elif completed.returncode not in {0, 1} and not completed.stdout:
                error = f"Codex exited with code {completed.returncode}"
            else:
                parsed = _extract_json(completed.stdout)
    else:
        command = ["gemini", "--output-format", "json", "--approval-mode", "plan", "--prompt", full_prompt]
        if not use_default and variant:
            command[1:1] = ["--model", variant]
        completed = _run(command, None, timeout)
        if completed.returncode == 124:
            error = f"Gemini review timed out after {timeout}s"
        elif completed.returncode not in {0, 1} and not completed.stdout:
            error = f"Gemini exited with code {completed.returncode}"
        else:
            parsed = _extract_json(completed.stdout)

    if error:
        harness.emit("review.failed", phase="review", provider=provider, role=args.role, file=args.file_path, error=error)
        return _error(provider, args.role, error, 0)
    if parsed is None:
        harness.emit("review.failed", phase="review", provider=provider, role=args.role, file=args.file_path, error="parse_error")
        return _error(provider, args.role, f"Failed to parse JSON from {provider} response", 0)
    result = attach_evidence_to_findings(_normalize(provider, args.role, args.file_path, parsed), evidence)
    harness.emit("review.completed", phase="review", provider=provider, role=args.role, file=args.file_path, finding_count=len(result.get("findings", [])))
    harness.checkpoint("review_completed", provider=provider, role=args.role, file=args.file_path)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0
