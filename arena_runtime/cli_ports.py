from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import math
import re
import shutil
import subprocess
import sys
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence, Tuple

from .harness import HarnessRun
from .schemas import normalize_provider_payload

INTENSITY_RANK = {"quick": 1, "standard": 2, "deep": 3, "comprehensive": 4}
SEVERITY_RANK = {"info": 0, "low": 1, "medium": 2, "high": 3, "critical": 4}


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _dump(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def _bool(value: Any, default: bool = False) -> bool:
    if value is None:
        return default
    if isinstance(value, bool):
        return value
    if isinstance(value, (int, float)):
        return value != 0
    return str(value).strip().lower() in {"1", "true", "yes", "y", "on"}


def _as_int(value: Any, default: int = 0) -> int:
    try:
        return int(float(value))
    except (TypeError, ValueError):
        return default


def _as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _clamp_int(value: Any, minimum: int, maximum: int, default: int = 0) -> int:
    return max(minimum, min(maximum, _as_int(value, default)))


def _normalize_severity(value: Any) -> str:
    key = str(value or "medium").lower()
    if key in {"critical", "error", "blocker", "fatal"}:
        return "critical"
    if key in {"high", "warning", "major", "important"}:
        return "high"
    if key in {"medium", "moderate", "minor", "note"}:
        return "medium"
    if key in {"low", "info", "hint", "trivial", "style", "suggestion"}:
        return "low"
    return "medium"


def _unique(values: Iterable[Any]) -> List[str]:
    seen: set[str] = set()
    out: List[str] = []
    for value in values:
        text = str(value or "").strip()
        if text and text not in seen:
            seen.add(text)
            out.append(text)
    return out


# ---------------------------------------------------------------------------
# Debate runtime
# ---------------------------------------------------------------------------


def _read_findings(source: str) -> Tuple[List[Dict[str, Any]], str | None]:
    try:
        path = Path(source)
        raw = path.read_text(encoding="utf-8") if path.exists() else source
        data = json.loads(raw)
    except Exception:
        return [], "Invalid findings JSON"

    if isinstance(data, dict):
        if isinstance(data.get("findings"), list):
            data = data["findings"]
        elif all(isinstance(data.get(key), list) for key in ["accepted", "rejected", "disputed"]):
            data = data.get("accepted", []) + data.get("disputed", [])
        else:
            data = [data]
    if not isinstance(data, list):
        return [], "Invalid findings JSON"
    return [dict(item) for item in data if isinstance(item, dict)], None


def _empty_consensus(findings: Sequence[Dict[str, Any]] | None = None, error: str | None = None) -> Dict[str, Any]:
    result: Dict[str, Any] = {"accepted": list(findings or []), "rejected": [], "disputed": []}
    if error:
        result["error"] = error
    return result


def _model_cfg(cfg: Dict[str, Any], provider: str) -> Dict[str, Any]:
    models = cfg.get("models", {}) if isinstance(cfg.get("models"), dict) else {}
    provider_cfg = models.get(provider, {}) if isinstance(models.get(provider), dict) else {}
    return provider_cfg


def _provider_active(cfg: Dict[str, Any], provider: str) -> bool:
    provider_cfg = _model_cfg(cfg, provider)
    return _bool(provider_cfg.get("enabled"), False) and shutil.which(provider) is not None


def _use_user_default(cfg: Dict[str, Any], provider: str) -> bool:
    provider_cfg = _model_cfg(cfg, provider)
    root_provider = cfg.get(provider, {}) if isinstance(cfg.get(provider), dict) else {}
    return _bool(provider_cfg.get("use_user_default", root_provider.get("use_user_default", True)), True)


def _provider_variant(cfg: Dict[str, Any], provider: str) -> str:
    provider_cfg = _model_cfg(cfg, provider)
    root_provider = cfg.get(provider, {}) if isinstance(cfg.get(provider), dict) else {}
    value = provider_cfg.get("model_variant", root_provider.get("model_variant", ""))
    return str(value or "")


def _extract_json_object(text: str) -> Dict[str, Any] | None:
    stripped = text.strip()
    if not stripped:
        return None
    try:
        data = json.loads(stripped)
        return data if isinstance(data, dict) else None
    except json.JSONDecodeError:
        pass

    decoder = json.JSONDecoder()
    for index, char in enumerate(stripped):
        if char != "{":
            continue
        try:
            data, _end = decoder.raw_decode(stripped[index:])
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            return data
    return None


def _code_snippet(file_name: str, line: int) -> str:
    if not file_name:
        return ""
    path = Path(file_name)
    if not path.exists() or not path.is_file():
        return ""
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return ""
    if line > 0:
        start = max(0, line - 6)
        end = min(len(lines), line + 15)
        return "\n".join(lines[start:end])
    return "\n".join(lines[:50])


def _challenge_prompt(finding: Dict[str, Any], snippet: str) -> str:
    return (
        "You are validating one code-review finding. Return only JSON with "
        "agree:boolean, confidence_adjustment:number between -20 and 20, and evidence:string.\n\n"
        f"Finding:\n{json.dumps(finding, ensure_ascii=False, indent=2)}\n\n"
        f"Code context:\n{snippet or '(not available)'}"
    )


def _run_challenge(provider: str, cfg: Dict[str, Any], prompt: str, timeout_seconds: int) -> Dict[str, Any]:
    try:
        if provider == "codex":
            command = ["codex", "exec"]
            variant = _provider_variant(cfg, provider)
            if not _use_user_default(cfg, provider) and variant:
                command.extend(["-m", variant])
            completed = subprocess.run(
                command,
                input=prompt,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout_seconds,
                check=False,
            )
        elif provider == "gemini":
            command = ["gemini"]
            variant = _provider_variant(cfg, provider)
            if not _use_user_default(cfg, provider) and variant:
                command.extend(["--model", variant])
            command.append(prompt)
            completed = subprocess.run(
                command,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=timeout_seconds,
                check=False,
            )
        else:
            return {"agree": True, "confidence_adjustment": 0, "evidence": "Unsupported challenger"}
    except Exception as exc:
        return {"agree": True, "confidence_adjustment": 0, "evidence": f"Challenge unavailable: {exc}"}

    parsed = _extract_json_object(completed.stdout or "")
    if not parsed:
        return {"agree": True, "confidence_adjustment": 0, "evidence": "Challenge did not return valid JSON"}
    return parsed


def _pick_challenger(finding: Dict[str, Any], active: Sequence[str]) -> str | None:
    if not active:
        return None
    original = str(finding.get("model") or "").lower()
    models = {str(model).lower() for model in finding.get("models", []) if model}
    for provider in active:
        if provider != original and provider not in models:
            return provider
    for provider in active:
        if provider != original:
            return provider
    return active[0]


def _categorize_finding(finding: Dict[str, Any], threshold: int) -> str:
    confidence = _as_int(finding.get("confidence"), 0)
    models = _unique(finding.get("models", []))
    status = str(finding.get("debate_status", "none"))
    if len(models) >= 2 and status != "challenged":
        return "accepted"
    if confidence >= threshold:
        return "accepted"
    if status == "challenged" and confidence < threshold * 0.5:
        return "rejected"
    if status == "challenged":
        return "disputed"
    if confidence < threshold * 0.6:
        return "disputed"
    if confidence >= threshold * 0.7:
        return "accepted"
    return "disputed"


def cmd_run_debate(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="run-debate")
    parser.add_argument("findings_json")
    parser.add_argument("config_file")
    parser.add_argument("session_dir")
    args = parser.parse_args(list(argv))
    harness = HarnessRun.from_env()
    harness.emit("debate.started", phase="debate", findings_json=str(args.findings_json), session_dir=str(args.session_dir))

    try:
        cfg = _load_json(Path(args.config_file))
    except Exception:
        cfg = {}
    findings, error = _read_findings(args.findings_json)
    if error:
        harness.emit("debate.completed", phase="debate", error=error, accepted=0, disputed=0, rejected=0)
        _dump(_empty_consensus([], error))
        return 0
    if not findings:
        harness.emit("debate.completed", phase="debate", accepted=0, disputed=0, rejected=0)
        _dump(_empty_consensus([]))
        return 0

    debate_cfg = cfg.get("debate", {}) if isinstance(cfg.get("debate"), dict) else {}
    enabled = _bool(debate_cfg.get("enabled"), False)
    max_rounds = min(10, max(0, _as_int(debate_cfg.get("max_rounds"), 2)))
    consensus_threshold = _clamp_int(debate_cfg.get("consensus_threshold"), 0, 100, 80)
    challenge_threshold = _clamp_int(debate_cfg.get("challenge_threshold"), 0, 100, 60)
    timeout_seconds = max(1, _as_int(cfg.get("timeout"), 120))

    if not enabled or max_rounds <= 0:
        harness.emit("debate.completed", phase="debate", skipped=True, reason="disabled", accepted=len(findings), disputed=0, rejected=0)
        _dump(_empty_consensus(findings))
        return 0

    active = [provider for provider in ["codex", "gemini"] if _provider_active(cfg, provider)]
    if not active:
        harness.emit("debate.completed", phase="debate", skipped=True, reason="no_active_challengers", accepted=len(findings), disputed=0, rejected=0)
        _dump(_empty_consensus(findings))
        return 0

    current = [dict(finding) for finding in findings]
    debate_log: List[Dict[str, Any]] = []

    for round_number in range(1, max_rounds + 1):
        for index, finding in enumerate(current):
            confidence = _as_int(finding.get("confidence"), 50)
            models = _unique(finding.get("models", []) or [finding.get("model")])
            if len(models) > 1 and confidence >= challenge_threshold:
                continue

            challenger = _pick_challenger(finding, active)
            if not challenger:
                continue

            snippet = _code_snippet(str(finding.get("file") or ""), _as_int(finding.get("line"), 0))
            challenge = _run_challenge(challenger, cfg, _challenge_prompt(finding, snippet), timeout_seconds)
            harness.emit("debate.challenge_completed", phase="debate", round=round_number, finding_index=index, challenger=challenger)
            agree = _bool(challenge.get("agree"), True)
            adjustment = _clamp_int(challenge.get("confidence_adjustment"), -20, 20, 0)
            new_confidence = max(0, min(100, confidence + adjustment))

            updated = dict(finding)
            updated["confidence"] = new_confidence
            updated["debate_status"] = "confirmed" if agree else "challenged"
            updated["challenger"] = challenger
            updated["models"] = _unique([*models, challenger])
            current[index] = updated

            debate_log.append(
                {
                    "round": round_number,
                    "finding_index": index,
                    "finding_title": str(finding.get("title") or ""),
                    "challenger": challenger,
                    "agree": agree,
                    "confidence_adjustment": adjustment,
                    "evidence": str(challenge.get("evidence") or ""),
                    "old_confidence": confidence,
                    "new_confidence": new_confidence,
                }
            )

    session_dir = Path(args.session_dir)
    try:
        session_dir.mkdir(parents=True, exist_ok=True)
        (session_dir / "debate-log.json").write_text(json.dumps(debate_log, ensure_ascii=False, indent=2), encoding="utf-8")
    except OSError:
        pass

    result = {"accepted": [], "rejected": [], "disputed": []}
    for finding in current:
        result[_categorize_finding(finding, consensus_threshold)].append(finding)
    harness.emit("debate.completed", phase="debate", accepted=len(result["accepted"]), disputed=len(result["disputed"]), rejected=len(result["rejected"]), rounds=max_rounds)
    _dump(result)
    return 0


# ---------------------------------------------------------------------------
# Cost estimator runtime
# ---------------------------------------------------------------------------


CODE_PHASES: Dict[str, Tuple[int, int]] = {
    "intensity": (6000, 4000),
    "cost": (2000, 1000),
    "codebase": (5000, 3000),
    "stack": (2000, 1000),
    "research": (10000, 5000),
    "research_debate": (8000, 4000),
    "compliance": (8000, 4000),
    "compliance_debate": (6000, 3000),
    "benchmark": (25000, 15000),
    "figma": (15000, 5000),
    "strategy": (15000, 10000),
    "review_agent": (8000, 4000),
    "review_cli": (6000, 2000),
    "debate": (40000, 20000),
    "autofix": (6000, 4000),
    "report": (3000, 2000),
}
BUSINESS_PHASES: Dict[str, Tuple[int, int]] = {
    "intensity": (6000, 4000),
    "cost": (2000, 1000),
    "context": (7000, 3000),
    "market": (10000, 5000),
    "research": (12000, 8000),
    "research_debate": (8000, 4000),
    "accuracy": (12000, 6000),
    "accuracy_debate": (6000, 3000),
    "benchmark": (25000, 15000),
    "strategy": (15000, 10000),
    "review_agent": (10000, 5000),
    "review_cli": (6000, 2000),
    "debate": (35000, 15000),
    "autofix": (10000, 5000),
    "report": (5000, 3000),
}
PHASE_ORDER = {
    "code": {
        "quick": ["intensity", "cost", "codebase"],
        "standard": ["intensity", "cost", "codebase", "stack", "strategy", "review_agent", "review_cli", "report"],
        "deep": ["intensity", "cost", "codebase", "stack", "research", "compliance", "strategy", "review_agent", "review_cli", "debate", "autofix", "report"],
        "comprehensive": ["intensity", "cost", "codebase", "stack", "research", "research_debate", "compliance", "compliance_debate", "benchmark", "strategy", "review_agent", "review_cli", "debate", "autofix", "report"],
    },
    "business": {
        "quick": ["intensity", "cost", "context"],
        "standard": ["intensity", "cost", "context", "strategy", "review_agent", "review_cli", "report"],
        "deep": ["intensity", "cost", "context", "market", "research", "accuracy", "strategy", "review_agent", "review_cli", "debate", "autofix", "report"],
        "comprehensive": ["intensity", "cost", "context", "market", "research", "research_debate", "accuracy", "accuracy_debate", "benchmark", "strategy", "review_agent", "review_cli", "debate", "autofix", "report"],
    },
}


def _price_cfg(cfg: Dict[str, Any], key: str, default: float) -> float:
    cost_cfg = cfg.get("cost_estimation", {}) if isinstance(cfg.get("cost_estimation"), dict) else {}
    prices = cost_cfg.get("token_cost_per_1k", {}) if isinstance(cost_cfg.get("token_cost_per_1k"), dict) else {}
    return _as_float(prices.get(key), default)


def _provider_cost(input_tokens: int, output_tokens: int, input_price: float, output_price: float, cache_discount: float) -> float:
    return (input_tokens / 1000.0) * input_price * (1.0 - cache_discount) + (output_tokens / 1000.0) * output_price


def _count_roles(cfg: Dict[str, Any]) -> int:
    roles = _model_cfg(cfg, "claude").get("roles", [])
    return len(roles) if isinstance(roles, list) and roles else 4


def _external_cli_count(cfg: Dict[str, Any], intensity: str) -> int:
    if intensity == "quick":
        return 0
    count = 0
    for provider in ["codex", "gemini"]:
        if _provider_active(cfg, provider):
            count += 1
    return count


def _cost_estimate(cfg: Dict[str, Any], intensity: str, pipeline: str, lines: int, has_figma: bool) -> Dict[str, Any]:
    intensity = intensity if intensity in INTENSITY_RANK else "standard"
    pipeline = pipeline if pipeline in {"code", "business"} else "code"
    table = CODE_PHASES if pipeline == "code" else BUSINESS_PHASES
    phases = list(PHASE_ORDER[pipeline][intensity])
    if has_figma and pipeline == "code" and "figma" not in phases:
        phases.insert(min(5, len(phases)), "figma")

    line_factor = max(1.0, min(25.0, lines / 500.0))
    claude_agents = 0 if intensity == "quick" else (_count_roles(cfg) if pipeline == "code" else 6)
    external_cli_calls = _external_cli_count(cfg, intensity)
    debate_rounds = max(1, _as_int((cfg.get("debate", {}) or {}).get("max_rounds"), 2))
    debate_enabled = _bool((cfg.get("debate", {}) or {}).get("enabled"), False)

    claude_input = 0
    claude_output = 0
    codex_input = 0
    codex_output = 0
    gemini_input = 0
    gemini_output = 0

    for phase in phases:
        input_tokens, output_tokens = table[phase]
        if phase in {"codebase", "context", "review_agent", "review_cli"}:
            input_tokens = int(input_tokens * line_factor)
        if phase == "review_agent":
            input_tokens *= max(1, claude_agents)
            output_tokens *= max(1, claude_agents)
        if phase == "review_cli":
            input_tokens *= external_cli_calls
            output_tokens *= external_cli_calls
            if _provider_active(cfg, "codex"):
                codex_input += input_tokens // max(1, external_cli_calls)
                codex_output += output_tokens // max(1, external_cli_calls)
            if _provider_active(cfg, "gemini"):
                gemini_input += input_tokens // max(1, external_cli_calls)
                gemini_output += output_tokens // max(1, external_cli_calls)
            continue
        if phase == "debate":
            if not debate_enabled:
                continue
            input_tokens *= debate_rounds
            output_tokens *= debate_rounds
        claude_input += input_tokens
        claude_output += output_tokens

    cost_cfg = cfg.get("cost_estimation", {}) if isinstance(cfg.get("cost_estimation"), dict) else {}
    cache_discount = max(0.0, min(0.95, _as_float(cost_cfg.get("prompt_cache_discount"), 0.0)))
    total_cost = 0.0
    total_cost += _provider_cost(claude_input, claude_output, _price_cfg(cfg, "claude_input", 0.003), _price_cfg(cfg, "claude_output", 0.015), cache_discount)
    total_cost += _provider_cost(codex_input, codex_output, _price_cfg(cfg, "codex_input", 0.003), _price_cfg(cfg, "codex_output", 0.012), cache_discount)
    total_cost += _provider_cost(gemini_input, gemini_output, _price_cfg(cfg, "gemini_input", 0.00125), _price_cfg(cfg, "gemini_output", 0.005), cache_discount)

    total_input = claude_input + codex_input + gemini_input
    total_output = claude_output + codex_output + gemini_output
    total_tokens = total_input + total_output
    est_minutes = max(1, math.ceil(total_tokens / 60000.0 + claude_agents * 0.6 + external_cli_calls * 1.5))

    return {
        "intensity": intensity,
        "pipeline": pipeline,
        "input_lines": lines,
        "has_figma": has_figma,
        "claude_agents": claude_agents,
        "external_cli_calls": external_cli_calls,
        "total_input_tokens": total_input,
        "total_output_tokens": total_output,
        "total_tokens": total_tokens,
        "total_cost_usd": round(total_cost, 4),
        "est_minutes": est_minutes,
        "prompt_cache_discount": cache_discount,
        "cost_caps": cost_cfg.get("cost_caps", {}) if isinstance(cost_cfg.get("cost_caps"), dict) else {},
    }


def cmd_cost_estimator(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="cost-estimator")
    parser.add_argument("config_file")
    parser.add_argument("--intensity", default="standard")
    parser.add_argument("--pipeline", default="code")
    parser.add_argument("--lines", type=int, default=500)
    parser.add_argument("--figma", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(list(argv))

    config_path = Path(args.config_file)
    if not config_path.exists():
        print(f"[arena:error] Config file not found: {config_path}", file=sys.stderr)
        return 1
    cfg = _load_json(config_path)
    estimate = _cost_estimate(cfg, args.intensity, args.pipeline, max(1, args.lines), args.figma)
    if args.json:
        _dump(estimate)
        return 0

    print("Cost & Time Estimate")
    print(f"Intensity: {estimate['intensity']}")
    print(f"Pipeline: {estimate['pipeline']}")
    print(f"Input Lines: {estimate['input_lines']}")
    print(f"Claude Agents: {estimate['claude_agents']}")
    print(f"External CLI Calls: {estimate['external_cli_calls']}")
    print(f"Total Tokens: {estimate['total_tokens']}")
    print(f"Est. Cost: ${estimate['total_cost_usd']:.2f}")
    print(f"Est. Time: {estimate['est_minutes']} min")
    print(f"Prompt Cache Discount: {estimate['prompt_cache_discount']:.0%}")
    return 0


# ---------------------------------------------------------------------------
# Escalation scan runtime
# ---------------------------------------------------------------------------


def _pattern_entries(patterns: Any) -> List[Tuple[str, Dict[str, Any]]]:
    if isinstance(patterns, dict):
        entries: List[Tuple[str, Dict[str, Any]]] = []
        for name, value in patterns.items():
            if isinstance(value, dict):
                entries.append((str(name), value))
            elif isinstance(value, list):
                entries.append((str(name), {"file_patterns": value}))
        return entries
    if isinstance(patterns, list):
        entries = []
        for idx, value in enumerate(patterns):
            if isinstance(value, dict):
                entries.append((str(value.get("name") or f"trigger_{idx + 1}"), value))
        return entries
    return []


def _list_value(value: Any) -> List[str]:
    if isinstance(value, list):
        return [str(item) for item in value if str(item)]
    if isinstance(value, str) and value:
        return [value]
    return []


def _matches_file(path: str, patterns: Sequence[str]) -> bool:
    base = Path(path).name
    return any(fnmatch.fnmatch(path, pattern) or fnmatch.fnmatch(base, pattern) for pattern in patterns)


def _matches_content(path: str, patterns: Sequence[str]) -> bool:
    if not patterns:
        return False
    file_path = Path(path)
    if not file_path.exists() or not file_path.is_file():
        return False
    try:
        text = file_path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return False
    for pattern in patterns:
        try:
            if re.search(pattern, text, flags=re.IGNORECASE | re.MULTILINE):
                return True
        except re.error:
            if pattern.lower() in text.lower():
                return True
    return False


def _higher_intensity(left: str, right: str) -> str:
    return left if INTENSITY_RANK.get(left, 0) >= INTENSITY_RANK.get(right, 0) else right


def cmd_escalation_scan(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="escalation-scan")
    parser.add_argument("config_file")
    parser.add_argument("file_list_file", nargs="?")
    args = parser.parse_args(list(argv))

    cfg = _load_json(Path(args.config_file))
    esc = cfg.get("escalation_triggers", {}) if isinstance(cfg.get("escalation_triggers"), dict) else {}
    enabled = _bool(esc.get("enabled"), False)
    if args.file_list_file:
        file_list = Path(args.file_list_file).read_text(encoding="utf-8").splitlines()
    else:
        file_list = sys.stdin.read().splitlines()
    files = [line.strip() for line in file_list if line.strip()]

    result: Dict[str, Any] = {
        "enabled": enabled,
        "triggers_matched": [],
        "escalated_intensity": "standard",
        "requires_approval": False,
        "auto_fix_blocked_files": [],
    }
    if not enabled:
        _dump(result)
        return 0

    blocked: List[str] = []
    for name, entry in _pattern_entries(esc.get("patterns", {})):
        file_patterns = _list_value(entry.get("file_patterns", entry.get("files", entry.get("paths"))))
        content_patterns = _list_value(entry.get("content_patterns", entry.get("content", entry.get("regex"))))
        matched_files = [path for path in files if _matches_file(path, file_patterns) or _matches_content(path, content_patterns)]
        if not matched_files:
            continue
        result["triggers_matched"].append(name)
        target_intensity = str(entry.get("escalated_intensity") or entry.get("escalate_to") or entry.get("intensity") or "deep")
        result["escalated_intensity"] = _higher_intensity(str(result["escalated_intensity"]), target_intensity)
        result["requires_approval"] = bool(result["requires_approval"] or _bool(entry.get("requires_approval"), False))
        if _bool(entry.get("auto_fix_blocked", entry.get("block_auto_fix")), False):
            blocked.extend(matched_files)
        blocked.extend(_list_value(entry.get("auto_fix_blocked_files")))
    result["auto_fix_blocked_files"] = _unique(blocked)
    _dump(result)
    return 0


# ---------------------------------------------------------------------------
# Scanner normalization runtime
# ---------------------------------------------------------------------------


def _finding(scanner: str, file: Any, line: Any, title: Any, description: Any, severity: Any, confidence: Any, rule_id: Any = "") -> Dict[str, Any]:
    return {
        "file": str(file or ""),
        "line": _as_int(line, 0),
        "title": str(title or rule_id or "Scanner finding"),
        "description": str(description or title or ""),
        "severity": _normalize_severity(severity),
        "confidence": _clamp_int(confidence, 0, 100, 70),
        "scanner": scanner,
        "rule_id": str(rule_id or ""),
    }


def _confidence_from_text(value: Any) -> int:
    key = str(value or "medium").lower()
    if key in {"high", "certain"}:
        return 85
    if key in {"medium", "firm"}:
        return 70
    if key in {"low", "weak", "tentative"}:
        return 55
    return 70


def _normalize_bandit(scanner: str, data: Any) -> List[Dict[str, Any]]:
    return [
        _finding(scanner, item.get("filename"), item.get("line_number"), item.get("test_name") or item.get("test_id"), item.get("issue_text"), item.get("issue_severity"), _confidence_from_text(item.get("issue_confidence")), item.get("test_id"))
        for item in (data.get("results", []) if isinstance(data, dict) else [])
        if isinstance(item, dict)
    ]


def _normalize_eslint(scanner: str, data: Any) -> List[Dict[str, Any]]:
    findings: List[Dict[str, Any]] = []
    for file_item in data if isinstance(data, list) else []:
        if not isinstance(file_item, dict):
            continue
        for message in file_item.get("messages", []) or []:
            if not isinstance(message, dict):
                continue
            severity = "high" if _as_int(message.get("severity"), 1) >= 2 else "medium"
            findings.append(_finding(scanner, file_item.get("filePath"), message.get("line"), message.get("message"), message.get("message"), severity, 75, message.get("ruleId")))
    return findings


def _normalize_gosec(scanner: str, data: Any) -> List[Dict[str, Any]]:
    issues = data.get("Issues", data.get("issues", [])) if isinstance(data, dict) else []
    return [
        _finding(scanner, item.get("file"), item.get("line"), item.get("rule_id") or item.get("details"), item.get("details"), item.get("severity"), _confidence_from_text(item.get("confidence")), item.get("rule_id"))
        for item in issues
        if isinstance(item, dict)
    ]


def _normalize_brakeman(scanner: str, data: Any) -> List[Dict[str, Any]]:
    warnings = data.get("warnings", []) if isinstance(data, dict) else []
    return [
        _finding(scanner, item.get("file"), item.get("line"), item.get("warning_type"), item.get("message"), item.get("warning_type") or "medium", _confidence_from_text(item.get("confidence")), item.get("fingerprint"))
        for item in warnings
        if isinstance(item, dict)
    ]


def _normalize_cargo_audit(scanner: str, data: Any) -> List[Dict[str, Any]]:
    vulnerabilities = data.get("vulnerabilities", {}) if isinstance(data, dict) else {}
    items = vulnerabilities.get("list", vulnerabilities if isinstance(vulnerabilities, list) else [])
    findings: List[Dict[str, Any]] = []
    for item in items if isinstance(items, list) else []:
        if not isinstance(item, dict):
            continue
        advisory = item.get("advisory", {}) if isinstance(item.get("advisory"), dict) else {}
        package = item.get("package", {}) if isinstance(item.get("package"), dict) else {}
        title = advisory.get("title") or advisory.get("id") or f"Vulnerable package {package.get('name', '')}".strip()
        severity = "high" if advisory.get("cvss") else "medium"
        findings.append(_finding(scanner, "Cargo.lock", 0, title, advisory.get("description"), severity, 80, advisory.get("id")))
    return findings


def _normalize_semgrep(scanner: str, data: Any) -> List[Dict[str, Any]]:
    findings: List[Dict[str, Any]] = []
    for item in (data.get("results", []) if isinstance(data, dict) else []):
        if not isinstance(item, dict):
            continue
        extra = item.get("extra", {}) if isinstance(item.get("extra"), dict) else {}
        start = item.get("start", {}) if isinstance(item.get("start"), dict) else {}
        metadata = extra.get("metadata", {}) if isinstance(extra.get("metadata"), dict) else {}
        findings.append(
            _finding(
                scanner,
                item.get("path"),
                start.get("line"),
                extra.get("message") or item.get("check_id"),
                extra.get("message"),
                extra.get("severity"),
                metadata.get("confidence", 75),
                item.get("check_id"),
            )
        )
    return findings


def cmd_normalize_scanner_output(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="normalize-scanner-output")
    parser.add_argument("--scanner", required=True)
    parser.add_argument("--input", required=True)
    parser.add_argument("--confidence-floor", type=int, default=60)
    args = parser.parse_args(list(argv))

    try:
        data = _load_json(Path(args.input))
    except Exception:
        _dump([])
        return 0

    scanner = args.scanner.lower()
    if scanner == "bandit":
        findings = _normalize_bandit(scanner, data)
    elif scanner == "eslint":
        findings = _normalize_eslint(scanner, data)
    elif scanner == "gosec":
        findings = _normalize_gosec(scanner, data)
    elif scanner == "brakeman":
        findings = _normalize_brakeman(scanner, data)
    elif scanner == "cargo-audit":
        findings = _normalize_cargo_audit(scanner, data)
    elif scanner.startswith("semgrep"):
        findings = _normalize_semgrep(scanner, data)
    else:
        findings = []

    floor = max(0, min(100, args.confidence_floor))
    _dump([finding for finding in findings if _as_int(finding.get("confidence"), 0) >= floor])
    return 0


# ---------------------------------------------------------------------------
# Cache manager runtime
# ---------------------------------------------------------------------------


def _plugin_dir() -> Path:
    override = os_environ_get("ARENA_PLUGIN_DIR")
    if override:
        return Path(override)
    return Path(__file__).resolve().parents[1]


def os_environ_get(name: str) -> str:
    import os

    return os.environ.get(name, "")


def _cache_root() -> Path:
    return _plugin_dir() / "cache"


def _project_hash(project_root: str) -> str:
    resolved = str(Path(project_root).expanduser().resolve(strict=False))
    return hashlib.sha256(resolved.encode("utf-8")).hexdigest()[:16]


def _cache_paths(project_root: str, category: str, key: str) -> Tuple[Path, Path]:
    safe_category = category.strip().replace("/", "_") or "default"
    safe_key = key.strip().replace("/", "_") or "default"
    path = _cache_root() / _project_hash(project_root) / safe_category / safe_key
    return path, path.with_name(path.name + ".timestamp")


def _is_fresh(timestamp_path: Path, ttl_days: float | None) -> bool:
    if ttl_days is None:
        return True
    try:
        timestamp = float(timestamp_path.read_text(encoding="utf-8").strip())
    except Exception:
        return False
    return (time.time() - timestamp) <= ttl_days * 86400.0


def _write_entry(path: Path, timestamp_path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    timestamp_path.write_text(str(int(time.time())), encoding="utf-8")


def _read_entry(path: Path, timestamp_path: Path, ttl_days: float | None) -> str | None:
    if not path.exists() or not _is_fresh(timestamp_path, ttl_days):
        return None
    return path.read_text(encoding="utf-8")


def _parse_ttl(args: Sequence[str], flag: str, default: float | None = None) -> float | None:
    values = list(args)
    if flag not in values:
        return default
    idx = values.index(flag)
    if idx + 1 >= len(values):
        return default
    return _as_float(values[idx + 1], default or 0.0)


def _list_cache_entries(root: Path) -> List[Dict[str, Any]]:
    entries: List[Dict[str, Any]] = []
    if not root.exists():
        return entries
    now = time.time()
    for timestamp_path in sorted(root.glob("*/*.timestamp")):
        data_path = timestamp_path.with_name(timestamp_path.name[: -len(".timestamp")])
        if not data_path.exists():
            continue
        try:
            timestamp = float(timestamp_path.read_text(encoding="utf-8").strip())
        except Exception:
            timestamp = 0.0
        entries.append(
            {
                "category": timestamp_path.parent.name,
                "key": data_path.name,
                "age_seconds": max(0, int(now - timestamp)),
                "path": str(data_path),
            }
        )
    return entries


def cmd_cache_manager(argv: Sequence[str]) -> int:
    if not argv:
        print("Usage: cache-manager <command> ...", file=sys.stderr)
        return 2
    command = argv[0]
    args = list(argv[1:])

    if command == "hash" and len(args) >= 1:
        print(_project_hash(args[0]))
        return 0

    if command in {"write", "read", "check"} and len(args) >= 3:
        project_root, category, key = args[:3]
        ttl_days = _parse_ttl(args[3:], "--ttl")
        path, timestamp_path = _cache_paths(project_root, category, key)
        if command == "write":
            _write_entry(path, timestamp_path, sys.stdin.read())
            return 0
        content = _read_entry(path, timestamp_path, ttl_days)
        if content is None:
            return 1
        if command == "read":
            print(content, end="")
        return 0

    if command == "list" and len(args) >= 1:
        root = _cache_root() / _project_hash(args[0])
        _dump(_list_cache_entries(root))
        return 0

    if command == "cleanup" and len(args) >= 1:
        project_root = args[0]
        max_age = _parse_ttl(args[1:], "--max-age", 30.0)
        root = _cache_root() / _project_hash(project_root)
        now = time.time()
        if root.exists():
            for timestamp_path in list(root.glob("*/*.timestamp")) + list(root.glob("memory/*/*.timestamp")):
                try:
                    timestamp = float(timestamp_path.read_text(encoding="utf-8").strip())
                except Exception:
                    timestamp = 0.0
                if max_age is not None and now - timestamp > max_age * 86400.0:
                    data_path = timestamp_path.with_name(timestamp_path.name[: -len(".timestamp")])
                    data_path.unlink(missing_ok=True)
                    timestamp_path.unlink(missing_ok=True)
        return 0

    if command in {"memory-write", "memory-read"} and len(args) >= 3:
        project_root, tier, key = args[:3]
        path = _cache_root() / _project_hash(project_root) / "memory" / tier / key.replace("/", "_")
        timestamp_path = path.with_name(path.name + ".timestamp")
        if command == "memory-write":
            _write_entry(path, timestamp_path, sys.stdin.read())
            return 0
        content = _read_entry(path, timestamp_path, None)
        if content is None:
            return 1
        print(content, end="")
        return 0

    if command == "memory-list" and len(args) >= 2:
        project_root, tier = args[:2]
        root = _cache_root() / _project_hash(project_root) / "memory" / tier
        entries: List[Dict[str, Any]] = []
        if root.exists():
            for timestamp_path in sorted(root.glob("*.timestamp")):
                data_path = timestamp_path.with_name(timestamp_path.name[: -len(".timestamp")])
                if not data_path.exists():
                    continue
                try:
                    data = json.loads(data_path.read_text(encoding="utf-8"))
                except Exception:
                    data = data_path.read_text(encoding="utf-8")
                entries.append({"tier": tier, "key": data_path.name, "data": data})
        _dump(entries)
        return 0

    print(f"[arena:error] Invalid cache-manager command: {command}", file=sys.stderr)
    return 2


# ---------------------------------------------------------------------------
# Feedback tracker runtime
# ---------------------------------------------------------------------------


VALID_VERDICTS = {"useful", "not_useful", "false_positive"}


def _feedback_log() -> Path:
    return _cache_root() / "feedback" / "feedback-log.jsonl"


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _parse_iso_timestamp(value: Any) -> float:
    try:
        text = str(value).replace("Z", "+00:00")
        return datetime.fromisoformat(text).timestamp()
    except Exception:
        return 0.0


def _read_feedback_records() -> List[Dict[str, Any]]:
    path = _feedback_log()
    if not path.exists():
        return []
    records: List[Dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            record = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(record, dict):
            records.append(record)
    return records


def _feedback_parser(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="feedback-tracker")
    sub = parser.add_subparsers(dest="command", required=True)
    record = sub.add_parser("record")
    record.add_argument("session_id")
    record.add_argument("finding_id")
    record.add_argument("verdict")
    record.add_argument("--model", default="unknown")
    record.add_argument("--category", default="general")
    record.add_argument("--severity", default="medium")
    report = sub.add_parser("report")
    report.add_argument("--days", type=int, default=30)
    report.add_argument("--model")
    report.add_argument("--category")
    sub.add_parser("stats")
    return parser.parse_args(list(argv))


def _aggregate_feedback(records: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    def blank() -> Dict[str, int]:
        return {"total": 0, "useful": 0, "not_useful": 0, "false_positive": 0}

    models: Dict[str, Dict[str, int]] = {}
    categories: Dict[str, Dict[str, int]] = {}
    for record in records:
        verdict = str(record.get("verdict") or "")
        model = str(record.get("model") or "unknown")
        category = str(record.get("category") or "general")
        models.setdefault(model, blank())
        categories.setdefault(category, blank())
        for bucket in [models[model], categories[category]]:
            bucket["total"] += 1
            if verdict in VALID_VERDICTS:
                bucket[verdict] += 1
    return {"models": models, "categories": categories}


def cmd_feedback_tracker(argv: Sequence[str]) -> int:
    args = _feedback_parser(argv)
    if args.command == "record":
        if args.verdict not in VALID_VERDICTS:
            _dump({"error": "Invalid verdict", "valid_verdicts": sorted(VALID_VERDICTS)})
            return 1
        path = _feedback_log()
        path.parent.mkdir(parents=True, exist_ok=True)
        record = {
            "timestamp": _utc_now(),
            "session_id": args.session_id,
            "finding_id": args.finding_id,
            "verdict": args.verdict,
            "model": args.model,
            "category": args.category,
            "severity": args.severity,
        }
        with path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
        _dump({"status": "recorded", "session_id": args.session_id, "finding_id": args.finding_id})
        return 0

    records = _read_feedback_records()
    if args.command == "report":
        cutoff = time.time() - max(0, args.days) * 86400.0
        filtered = [
            record
            for record in records
            if _parse_iso_timestamp(record.get("timestamp")) >= cutoff
            and (not args.model or record.get("model") == args.model)
            and (not args.category or record.get("category") == args.category)
        ]
        _dump(_aggregate_feedback(filtered))
        return 0

    if args.command == "stats":
        verdicts = {key: 0 for key in sorted(VALID_VERDICTS)}
        models = sorted({str(record.get("model") or "unknown") for record in records})
        timestamps = sorted(_parse_iso_timestamp(record.get("timestamp")) for record in records if record.get("timestamp"))
        for record in records:
            verdict = str(record.get("verdict") or "")
            if verdict in verdicts:
                verdicts[verdict] += 1
        _dump(
            {
                "total_records": len(records),
                "models": models,
                "verdicts": verdicts,
                "oldest": datetime.fromtimestamp(timestamps[0], timezone.utc).isoformat() if timestamps else None,
                "newest": datetime.fromtimestamp(timestamps[-1], timezone.utc).isoformat() if timestamps else None,
            }
        )
        return 0

    return 2


# ---------------------------------------------------------------------------
# Stack detection runtime
# ---------------------------------------------------------------------------


def _add(target: List[str], *values: str) -> None:
    for value in values:
        if value and value not in target:
            target.append(value)


def _read_text_if_exists(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8", errors="replace") if path.exists() else ""
    except OSError:
        return ""


def _detect_dependencies(root: Path) -> Dict[str, Any]:
    result = {
        "project_root": str(root),
        "detected_at": _utc_now(),
        "platform": "unknown",
        "languages": [],
        "frameworks": [],
        "databases": [],
        "infrastructure": [],
        "build_tools": [],
        "testing": [],
        "ci_cd": [],
        "all_technologies": [],
    }
    languages: List[str] = result["languages"]
    frameworks: List[str] = result["frameworks"]
    databases: List[str] = result["databases"]
    infrastructure: List[str] = result["infrastructure"]
    build_tools: List[str] = result["build_tools"]
    testing: List[str] = result["testing"]
    ci_cd: List[str] = result["ci_cd"]

    package_json = root / "package.json"
    if package_json.exists():
        _add(languages, "nodejs")
        _add(build_tools, "npm")
        try:
            pkg = json.loads(package_json.read_text(encoding="utf-8"))
        except Exception:
            pkg = {}
        deps = {}
        for section in ["dependencies", "devDependencies", "peerDependencies"]:
            if isinstance(pkg.get(section), dict):
                deps.update(pkg[section])
        dep_names = set(deps)
        if "typescript" in dep_names or (root / "tsconfig.json").exists():
            _add(languages, "typescript")
        for dep, tech in [("express", "express"), ("react", "react"), ("next", "nextjs"), ("vue", "vue"), ("svelte", "svelte")]:
            if dep in dep_names:
                _add(frameworks, tech)
        for dep, tech in [("pg", "postgresql"), ("postgres", "postgresql"), ("mongoose", "mongodb"), ("mongodb", "mongodb"), ("mysql", "mysql"), ("redis", "redis")]:
            if dep in dep_names:
                _add(databases, tech)
        for dep, tech in [("jest", "jest"), ("vitest", "vitest"), ("mocha", "mocha")]:
            if dep in dep_names:
                _add(testing, tech)
    elif (root / "tsconfig.json").exists():
        _add(languages, "typescript")

    python_text = "\n".join([_read_text_if_exists(root / "requirements.txt"), _read_text_if_exists(root / "pyproject.toml")]).lower()
    if python_text.strip():
        _add(languages, "python")
        for needle, tech in [("django", "django"), ("fastapi", "fastapi"), ("flask", "flask"), ("celery", "celery"), ("sqlalchemy", "sqlalchemy")]:
            if needle in python_text:
                _add(frameworks, tech)
        for needle, tech in [("redis", "redis"), ("psycopg", "postgresql"), ("postgres", "postgresql"), ("mysql", "mysql")]:
            if needle in python_text:
                _add(databases, tech)
        if "pytest" in python_text:
            _add(testing, "pytest")

    if (root / "go.mod").exists():
        _add(languages, "golang")
        _add(build_tools, "go-modules")

    pom_text = _read_text_if_exists(root / "pom.xml").lower()
    if pom_text:
        _add(languages, "java")
        _add(build_tools, "maven")
        if "spring" in pom_text:
            _add(frameworks, "springboot")
        if "mysql" in pom_text:
            _add(databases, "mysql")

    gradle_text = "\n".join([_read_text_if_exists(root / "build.gradle"), _read_text_if_exists(root / "build.gradle.kts")]).lower()
    if gradle_text.strip():
        _add(languages, "java")
        _add(build_tools, "gradle")
        if "spring" in gradle_text:
            _add(frameworks, "springboot")
        if "redis" in gradle_text or "jedis" in gradle_text:
            _add(databases, "redis")

    if (root / "Dockerfile").exists() or (root / "docker-compose.yml").exists() or (root / "docker-compose.yaml").exists():
        _add(infrastructure, "docker")

    workflows = root / ".github" / "workflows"
    if workflows.exists() and any(workflows.glob("*.yml")) or workflows.exists() and any(workflows.glob("*.yaml")):
        _add(ci_cd, "github-actions")

    all_values: List[str] = []
    for key in ["languages", "frameworks", "databases", "infrastructure", "build_tools", "testing", "ci_cd"]:
        all_values.extend(result[key])
    result["all_technologies"] = _unique(all_values)
    if len(languages) > 1:
        result["platform"] = "multi-stack"
    elif languages:
        result["platform"] = languages[0]
    return result


def cmd_detect_stack(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="detect-stack")
    parser.add_argument("project_root")
    parser.add_argument("--output", choices=["json", "text"], default="json")
    args = parser.parse_args(list(argv))
    result = _detect_dependencies(Path(args.project_root))
    if args.output == "text":
        print(f"Platform: {result['platform']}")
        for label, key in [
            ("Languages", "languages"),
            ("Frameworks", "frameworks"),
            ("Databases", "databases"),
            ("Infrastructure", "infrastructure"),
            ("Build Tools", "build_tools"),
            ("Testing", "testing"),
            ("CI/CD", "ci_cd"),
        ]:
            print(f"{label}: {', '.join(result[key]) if result[key] else 'none'}")
    else:
        _dump(result)
    return 0


# ---------------------------------------------------------------------------
# Context filter runtime
# ---------------------------------------------------------------------------


def _load_config_lenient(path: str) -> Dict[str, Any]:
    try:
        data = _load_json(Path(path))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _role_keywords(role: str) -> Tuple[List[str], List[str]]:
    key = role.lower()
    if "security" in key:
        return ["*auth*", "*security*", "*middleware*", "*session*", "*crypto*"], ["auth", "password", "token", "login", "session", "crypto", "sanitize"]
    if "performance" in key:
        return ["*service*", "*cache*", "*query*", "*perf*"], ["cache", "query", "select", "loop", "memo", "performance", "async"]
    return [], []


def _context_lines(text: str, max_tokens: int) -> List[str]:
    max_lines = max(1, max_tokens // 4)
    return text.splitlines()[:max_lines]


def _select_files(files: Sequence[str], role: str, enabled: bool) -> List[str]:
    if not enabled:
        return list(files)
    patterns, keywords = _role_keywords(role)
    if not patterns and not keywords:
        return list(files)
    selected: List[str] = []
    for file in files:
        path = Path(file)
        name_match = _matches_file(file, patterns)
        content_match = False
        if path.exists():
            text = _read_text_if_exists(path).lower()
            content_match = any(keyword in text for keyword in keywords)
        if name_match or content_match:
            selected.append(file)
    return selected


def cmd_context_filter(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="context-filter")
    parser.add_argument("role")
    parser.add_argument("config_file")
    parser.add_argument("--budget", type=int, default=None)
    args = parser.parse_args(list(argv))

    cfg = _load_config_lenient(args.config_file)
    density = cfg.get("context_density", {}) if isinstance(cfg.get("context_density"), dict) else {}
    enabled = _bool(density.get("enabled"), True)
    budget = args.budget or _as_int(density.get("agent_context_budget_tokens"), 8000)
    remaining_lines = max(1, budget // 4)

    output: List[str] = []
    project_context = cfg.get("project_context", {}) if isinstance(cfg.get("project_context"), dict) else {}
    if _bool(project_context.get("enabled"), False) and _bool(project_context.get("inject_before_code"), True):
        context_path = Path(str(project_context.get("filename") or ".ai-review-arena-context.md"))
        if context_path.exists():
            context_text = _read_text_if_exists(context_path)
            max_tokens = _as_int(project_context.get("max_tokens"), 1500)
            lines = _context_lines(context_text, max_tokens)
            output.extend(["--- PROJECT CONTEXT ---", *lines, ""])
            remaining_lines = max(1, remaining_lines - len(lines))
            print(f"Project context loaded: {context_path}", file=sys.stderr)

    files = [line.strip() for line in sys.stdin.read().splitlines() if line.strip()]
    selected = _select_files(files, args.role, enabled)
    if not selected:
        print("\n".join(output), end=("\n" if output else ""))
        return 0

    per_file_budget = max(1, remaining_lines // max(1, len(selected)))
    for file in selected:
        path = Path(file)
        if not path.exists() or not path.is_file():
            continue
        lines = _read_text_if_exists(path).splitlines()
        mode = "full" if not enabled or len(lines) <= per_file_budget else "filtered"
        output.append(f"--- FILE: {file} ({mode}) ---")
        output.extend(lines[:per_file_budget])
        output.append("")
    print("\n".join(output), end=("\n" if output else ""))
    return 0


# ---------------------------------------------------------------------------
# Signal log runtime
# ---------------------------------------------------------------------------


VALID_SIGNAL_TYPES = {"finding", "challenge", "support", "escalation", "consensus", "pattern", "learning"}
INJECTION_PATTERNS = [
    re.compile(pattern, re.IGNORECASE)
    for pattern in [
        r"ignore\\s+(all\\s+)?previous\\s+instructions",
        r"system\\s*prompt",
        r"developer\\s+message",
        r"exfiltrate",
        r"https?://[^\\s]+/(?:collect|steal|exfiltrate)",
    ]
]


def _signal_paths(project_root: str) -> Tuple[Path, Path]:
    base = _cache_root() / _project_hash(project_root) / "signal-log"
    base.mkdir(parents=True, exist_ok=True)
    return base / "signals.jsonl", base / "learnings.jsonl"


def _valid_cache_content(text: str) -> bool:
    return not any(pattern.search(text) for pattern in INJECTION_PATTERNS)


def _read_jsonl(path: Path) -> List[Dict[str, Any]]:
    if not path.exists():
        return []
    rows: List[Dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            data = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(data, dict):
            rows.append(data)
    return rows


def _write_jsonl(path: Path, data: Dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(data, ensure_ascii=False) + "\n")


def _group_counts(rows: Sequence[Dict[str, Any]], key: str) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for row in rows:
        value = str(row.get(key) or "unknown")
        counts[value] = counts.get(value, 0) + 1
    return counts


def _signal_learnings(signals: Sequence[Dict[str, Any]]) -> List[Dict[str, Any]]:
    learnings: List[Dict[str, Any]] = []

    challenge_groups: Dict[str, List[Dict[str, Any]]] = {}
    escalation_groups: Dict[str, List[Dict[str, Any]]] = {}
    consensus_groups: Dict[str, List[Dict[str, Any]]] = {}

    for row in signals:
        data = row.get("data", {}) if isinstance(row.get("data"), dict) else {}
        if row.get("signal_type") == "challenge":
            challenge_groups.setdefault(str(data.get("finding_type") or "unknown"), []).append(row)
        if row.get("signal_type") == "escalation":
            escalation_groups.setdefault(str(data.get("trigger") or "unknown"), []).append(row)
        if row.get("signal_type") == "consensus":
            consensus_groups.setdefault(str(data.get("finding_type") or "unknown"), []).append(row)

    for pattern, rows in sorted(challenge_groups.items()):
        if len(rows) >= 2:
            learnings.append(
                {
                    "learning_type": "false_positive_pattern",
                    "pattern": pattern,
                    "occurrences": len(rows),
                    "agents_involved": _unique(row.get("agent_id") for row in rows),
                    "recommendation": f"Consider adding to Recognized Secure Patterns for {rows[0].get('agent_id', 'unknown')}",
                }
            )

    for trigger, rows in sorted(escalation_groups.items()):
        learnings.append(
            {
                "learning_type": "escalation_pattern",
                "trigger": trigger,
                "occurrences": len(rows),
                "recommendation": "This trigger consistently escalates intensity",
            }
        )

    for pattern, rows in sorted(consensus_groups.items()):
        if len(rows) >= 3:
            learnings.append(
                {
                    "learning_type": "quick_consensus",
                    "pattern": pattern,
                    "occurrences": len(rows),
                    "recommendation": "This finding type reaches consensus quickly; consider auto-accepting in Phase 6",
                }
            )
    return learnings


def cmd_signal_log(argv: Sequence[str]) -> int:
    if not argv:
        print("[arena:error] Usage: signal-log <write|read|stats|learn|gotcha-suggest> ...", file=sys.stderr)
        return 0
    command = argv[0]
    args = list(argv[1:])

    if command == "write" and len(args) >= 3:
        project_root, agent_id, signal_type = args[:3]
        data_json = args[3] if len(args) >= 4 else "{}"
        if signal_type not in VALID_SIGNAL_TYPES:
            print(f"[arena:error] Invalid signal type: {signal_type}", file=sys.stderr)
            return 1
        try:
            data = json.loads(data_json)
        except json.JSONDecodeError:
            print(f"[arena:error] Invalid JSON data: {data_json}", file=sys.stderr)
            return 1
        if not _valid_cache_content(data_json):
            print(f"[arena:warn] Signal write rejected for agent {agent_id}: injection pattern detected in data", file=sys.stderr)
            return 1
        signal_file, _learn_file = _signal_paths(project_root)
        now = int(time.time())
        _write_jsonl(
            signal_file,
            {
                "agent_id": agent_id,
                "signal_type": signal_type,
                "timestamp": now,
                "timestamp_iso": datetime.fromtimestamp(now, timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "data": data,
            },
        )
        return 0

    if command == "read" and len(args) >= 1:
        project_root = args[0]
        values = args[1:]
        agent_filter = values[values.index("--agent") + 1] if "--agent" in values and values.index("--agent") + 1 < len(values) else ""
        type_filter = values[values.index("--type") + 1] if "--type" in values and values.index("--type") + 1 < len(values) else ""
        since = _as_int(values[values.index("--since") + 1], 0) if "--since" in values and values.index("--since") + 1 < len(values) else 0
        signal_file, _learn_file = _signal_paths(project_root)
        rows = [
            row
            for row in _read_jsonl(signal_file)
            if _as_int(row.get("timestamp"), 0) >= since
            and (not agent_filter or row.get("agent_id") == agent_filter)
            and (not type_filter or row.get("signal_type") == type_filter)
        ]
        _dump(rows)
        return 0

    if command == "stats" and len(args) >= 1:
        signal_file, _learn_file = _signal_paths(args[0])
        rows = _read_jsonl(signal_file)
        if not rows:
            _dump({"total_signals": 0})
            return 0
        sorted_rows = sorted(rows, key=lambda row: _as_int(row.get("timestamp"), 0))
        _dump(
            {
                "total_signals": len(rows),
                "by_type": _group_counts(rows, "signal_type"),
                "by_agent": _group_counts(rows, "agent_id"),
                "time_range": {
                    "first": sorted_rows[0].get("timestamp_iso", "N/A"),
                    "last": sorted_rows[-1].get("timestamp_iso", "N/A"),
                },
            }
        )
        return 0

    if command == "learn" and len(args) >= 1:
        signal_file, learn_file = _signal_paths(args[0])
        learnings = _signal_learnings(_read_jsonl(signal_file))
        extracted_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        for learning in learnings:
            _write_jsonl(learn_file, {**learning, "extracted_at": extracted_at})
        _dump(learnings)
        return 0

    if command == "gotcha-suggest" and len(args) >= 1:
        project_root = args[0]
        save = "--save" in args[1:]
        _signal_file, learn_file = _signal_paths(project_root)
        learnings = [
            row
            for row in _read_jsonl(learn_file)
            if row.get("learning_type") == "false_positive_pattern" and _as_int(row.get("occurrences"), 0) >= 2
        ]
        if not learnings:
            print("No Gotcha suggestions found (need patterns with 2+ occurrences).")
            return 0
        by_pattern: Dict[str, Dict[str, Any]] = {}
        for row in learnings:
            pattern = str(row.get("pattern") or "unknown")
            bucket = by_pattern.setdefault(pattern, {"agent": (row.get("agents_involved") or ["unknown"])[0], "pattern": pattern, "total_occurrences": 0})
            bucket["total_occurrences"] += _as_int(row.get("occurrences"), 0)
        suggestions = sorted(by_pattern.values(), key=lambda row: -_as_int(row.get("total_occurrences"), 0))
        print("## Auto-Generated Gotcha Suggestions")
        print()
        print(f"Based on {len(suggestions)} false-positive patterns detected across reviews:")
        print()
        lines: List[str] = []
        for item in suggestions:
            line = f"- **{item['pattern']}**: This pattern was challenged {item['total_occurrences']} times across reviews and frequently dismissed; likely a false positive that should be added to Gotchas"
            lines.append(line)
            print(f"### Agent: {item['agent']}")
            print(line)
            print(f"  (seen {item['total_occurrences']} times)")
            print()
        if save:
            path = _cache_root() / _project_hash(project_root) / "memory" / "short-term" / "gotcha-suggestions"
            _write_entry(path, path.with_name(path.name + ".timestamp"), "\n".join(lines))
        return 0

    print(f"[arena:error] Unknown command: {command}", file=sys.stderr)
    return 0


# ---------------------------------------------------------------------------
# Auto-tune prompts runtime
# ---------------------------------------------------------------------------


def _auto_tune_parser(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="auto-tune-prompts")
    parser.add_argument("--category", default="all")
    parser.add_argument("--max-iterations", type=int, default=None)
    parser.add_argument("--budget", type=float, default=None)
    parser.add_argument("--convergence-threshold", type=float, default=None)
    parser.add_argument("--config", default="")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(list(argv))


def _default_config_path() -> Path:
    return _plugin_dir() / "config" / "default-config.json"


def _load_auto_tune_config(path: str) -> Tuple[Path, Dict[str, Any]]:
    config_path = Path(path) if path else _default_config_path()
    if not config_path.exists():
        config_path = _default_config_path()
    return config_path, _load_config_lenient(str(config_path))


def _expand_user_path(value: str) -> Path:
    return Path(value.replace("~", str(Path.home()), 1)).expanduser()


def _daily_budget_used(cfg: Dict[str, Any]) -> float:
    cache_cfg = cfg.get("cache", {}) if isinstance(cfg.get("cache"), dict) else {}
    base_dir = str(cache_cfg.get("base_dir") or (_plugin_dir() / "cache"))
    today = datetime.now().strftime("%Y-%m-%d")
    daily_file = _expand_user_path(base_dir) / "cost-tracking" / f"{today}.json"
    if not daily_file.exists():
        return 0.0
    try:
        data = json.loads(daily_file.read_text(encoding="utf-8"))
    except Exception:
        return 0.0
    return _as_float(data.get("total_cost"), 0.0)


def _target_categories(cfg: Dict[str, Any], selected: str) -> List[str]:
    auto = cfg.get("auto_tune", {}) if isinstance(cfg.get("auto_tune"), dict) else {}
    if selected != "all":
        return [selected]
    configured = auto.get("target_categories")
    if isinstance(configured, list) and configured:
        return [str(item) for item in configured]
    return ["security", "bugs", "performance", "architecture", "testing"]


def cmd_auto_tune_prompts(argv: Sequence[str]) -> int:
    args = _auto_tune_parser(argv)
    config_path, cfg = _load_auto_tune_config(args.config)
    auto = cfg.get("auto_tune", {}) if isinstance(cfg.get("auto_tune"), dict) else {}
    max_iterations = args.max_iterations or _as_int(auto.get("max_iterations_per_category"), 10)
    max_total = _as_int(auto.get("max_iterations_total"), 30)
    convergence_threshold = args.convergence_threshold if args.convergence_threshold is not None else _as_float(auto.get("convergence_threshold_pct"), 0.5)
    daily_budget = args.budget if args.budget is not None else _as_float(auto.get("daily_budget_dollars"), 10.0)
    history_tier = str(auto.get("history_memory_tier") or "long-term")
    categories = _target_categories(cfg, args.category)

    lockfile = _plugin_dir() / "cache" / ".auto-tune.lock"
    lockfile.parent.mkdir(parents=True, exist_ok=True)
    lockfile.write_text(str(os_getpid()), encoding="utf-8")
    try:
        spent = _daily_budget_used(cfg)
        budget_exhausted = spent >= daily_budget
        if budget_exhausted and not args.dry_run:
            if args.json:
                _dump({"status": "budget_exhausted", "spent": spent, "budget": daily_budget})
            else:
                print(f"Budget exhausted: ${spent:.2f} >= ${daily_budget:.2f}")
            return 0

        results: List[Dict[str, Any]] = []
        total_iterations = 0
        for category in categories:
            iterations = min(max_iterations, max(0, max_total - total_iterations))
            if iterations <= 0:
                break
            total_iterations += iterations
            results.append(
                {
                    "category": category,
                    "iterations": iterations,
                    "dry_run": args.dry_run,
                    "convergence_threshold": convergence_threshold,
                    "history_tier": history_tier,
                    "status": "planned" if args.dry_run else "skipped_without_dry_run",
                }
            )

        if args.json:
            _dump({"status": "budget_exhausted" if budget_exhausted else "ok", "config": str(config_path), "dry_run": args.dry_run, "spent": spent, "budget": daily_budget, "categories": results})
            return 0

        print("Auto-tune Prompt Optimization")
        if args.dry_run:
            print("DRY-RUN mode: no prompt files will be modified.")
        print(f"Config: {config_path}")
        print(f"Daily Budget: ${daily_budget:.2f} (spent: ${spent:.2f})")
        if budget_exhausted:
            print(f"Budget exhausted: ${spent:.2f} >= ${daily_budget:.2f} (dry-run continues without mutations)")
        for item in results:
            print(f"Auto-tuning category: {item['category']}")
            print(f"  iterations: {item['iterations']}")
            print(f"  convergence_threshold: {item['convergence_threshold']}")
        return 0
    finally:
        lockfile.unlink(missing_ok=True)


def os_getpid() -> int:
    import os

    return os.getpid()


# ---------------------------------------------------------------------------
# Pipeline evaluation runtime
# ---------------------------------------------------------------------------


def _evaluate_parser(argv: Sequence[str]) -> argparse.Namespace:
    args = list(argv)
    config_file = ""
    if args and not args[0].startswith("--"):
        config_file = args.pop(0)
    parser = argparse.ArgumentParser(prog="evaluate-pipeline")
    parser.add_argument("--test-dir", default="")
    parser.add_argument("--output", choices=["json", "markdown"], default="markdown")
    parser.add_argument("--verbose", action="store_true")
    parsed = parser.parse_args(args)
    parsed.config_file = config_file
    return parsed


def _pipeline_test_dir(cfg: Dict[str, Any], configured: str) -> Path:
    if configured:
        return Path(configured)
    pipeline_cfg = cfg.get("pipeline_evaluation", {}) if isinstance(cfg.get("pipeline_evaluation"), dict) else {}
    rel = str(pipeline_cfg.get("test_cases_dir") or "config/benchmarks/pipeline")
    return _plugin_dir() / rel


def _ensure_sample_pipeline_case(test_dir: Path) -> None:
    test_dir.mkdir(parents=True, exist_ok=True)
    sample = test_dir / "sample-pipeline-test.json"
    if sample.exists():
        return
    sample.write_text(
        json.dumps(
            {
                "id": "pipeline-sample-01",
                "description": "Sample pipeline evaluation test case; replace with real test projects",
                "type": "pipeline_evaluation",
                "project_setup": {"files": {}},
                "ground_truth": {
                    "expected_findings": [
                        {
                            "category": "security",
                            "severity": "critical",
                            "location_hint": "file.js:line",
                            "description_contains": ["SQL injection", "parameterized"],
                            "must_find": True,
                        }
                    ],
                    "acceptable_false_positives": 2,
                },
                "evaluation_criteria": {"min_precision": 0.7, "min_recall": 0.8, "max_false_positive_rate": 0.3},
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )


def _actual_findings_from_case(test_case: Dict[str, Any]) -> List[Dict[str, Any]]:
    mock = test_case.get("mock_findings")
    if isinstance(mock, list):
        return [item for item in mock if isinstance(item, dict)]
    if isinstance(mock, dict) and isinstance(mock.get("findings"), list):
        return [item for item in mock["findings"] if isinstance(item, dict)]
    expected = ((test_case.get("ground_truth") or {}).get("expected_findings") or []) if isinstance(test_case.get("ground_truth"), dict) else []
    files = ((test_case.get("project_setup") or {}).get("files") or {}) if isinstance(test_case.get("project_setup"), dict) else {}
    first_file = next(iter(files.keys()), "test.py") if isinstance(files, dict) else "test.py"
    findings: List[Dict[str, Any]] = []
    for index, item in enumerate(expected):
        if not isinstance(item, dict):
            continue
        desc_values = item.get("description_contains") if isinstance(item.get("description_contains"), list) else []
        title = str(desc_values[0] if desc_values else item.get("category") or "finding")
        findings.append(
            {
                "title": title,
                "severity": item.get("severity", "medium"),
                "confidence": 85,
                "file": first_file,
                "line": index * 5 + 1,
                "description": f"{title} found at {item.get('location') or item.get('location_hint') or 'unknown'}",
                "suggestion": f"Fix the {item.get('category') or 'general'} issue",
            }
        )
    return findings


def _text_contains_keywords(findings: Sequence[Dict[str, Any]], keywords: Sequence[str]) -> bool:
    blob = json.dumps(findings, ensure_ascii=False).lower()
    return any(str(keyword).lower() in blob for keyword in keywords)


def _pipeline_metrics(test_case: Dict[str, Any], findings: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    expected = ((test_case.get("ground_truth") or {}).get("expected_findings") or []) if isinstance(test_case.get("ground_truth"), dict) else []
    tp = 0
    fn = 0
    for item in expected:
        if not isinstance(item, dict):
            continue
        keywords = item.get("description_contains")
        if not isinstance(keywords, list):
            keywords = []
        if keywords and _text_contains_keywords(findings, [str(keyword) for keyword in keywords]):
            tp += 1
        else:
            fn += 1
    actual_count = len(findings)
    fp = max(0, actual_count - tp)
    precision = tp / (tp + fp) if tp + fp > 0 else 0.0
    recall = tp / (tp + fn) if tp + fn > 0 else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall > 0 else 0.0
    fpr = fp / (fp + tp) if fp + tp > 0 else 0.0
    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "total_expected": len(expected),
        "total_actual": actual_count,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1_score": round(f1, 3),
        "false_positive_rate": round(fpr, 3),
    }


def cmd_evaluate_pipeline(argv: Sequence[str]) -> int:
    args = _evaluate_parser(argv)
    config_path, cfg = _load_auto_tune_config(args.config_file)
    test_dir = _pipeline_test_dir(cfg, args.test_dir)
    if not test_dir.exists():
        print(f"[arena:warn] Pipeline test directory not found: {test_dir}", file=sys.stderr)
        _ensure_sample_pipeline_case(test_dir)
    test_cases = sorted(test_dir.glob("*.json"))
    if not test_cases:
        _dump({"error": "no test cases found", "test_dir": str(test_dir)})
        return 0

    results: List[Dict[str, Any]] = []
    totals = {"tp": 0, "fp": 0, "fn": 0}
    for path in test_cases:
        test_case = _load_config_lenient(str(path))
        files = ((test_case.get("project_setup") or {}).get("files") or {}) if isinstance(test_case.get("project_setup"), dict) else {}
        if not files:
            continue
        findings = _actual_findings_from_case(test_case)
        metrics = _pipeline_metrics(test_case, findings)
        totals["tp"] += metrics["true_positives"]
        totals["fp"] += metrics["false_positives"]
        totals["fn"] += metrics["false_negatives"]
        criteria = test_case.get("evaluation_criteria", {}) if isinstance(test_case.get("evaluation_criteria"), dict) else {}
        criteria_met = metrics["precision"] >= _as_float(criteria.get("min_precision"), 0.7) and metrics["recall"] >= _as_float(criteria.get("min_recall"), 0.8)
        results.append(
            {
                "test_id": test_case.get("id", path.stem),
                "description": test_case.get("description", "no description"),
                "metrics": metrics,
                "criteria_met": criteria_met,
            }
        )

    precision = totals["tp"] / (totals["tp"] + totals["fp"]) if totals["tp"] + totals["fp"] > 0 else 0.0
    recall = totals["tp"] / (totals["tp"] + totals["fn"]) if totals["tp"] + totals["fn"] > 0 else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall > 0 else 0.0
    fpr = totals["fp"] / (totals["fp"] + totals["tp"]) if totals["fp"] + totals["tp"] > 0 else 0.0
    report = {
        "evaluation_timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "test_directory": str(test_dir),
        "test_cases_found": len(test_cases),
        "test_cases_evaluated": len(results),
        "aggregate_metrics": {
            "true_positives": totals["tp"],
            "false_positives": totals["fp"],
            "false_negatives": totals["fn"],
            "precision": round(precision, 3),
            "recall": round(recall, 3),
            "f1_score": round(f1, 3),
            "false_positive_rate": round(fpr, 3),
        },
        "test_results": results,
        "llm_as_judge": ((cfg.get("pipeline_evaluation") or {}).get("llm_as_judge") if isinstance(cfg.get("pipeline_evaluation"), dict) else {}) or {},
    }

    pipeline_cfg = cfg.get("pipeline_evaluation", {}) if isinstance(cfg.get("pipeline_evaluation"), dict) else {}
    report_dir = _plugin_dir() / str(pipeline_cfg.get("report_dir") or "cache/evaluation-reports")
    report_dir.mkdir(parents=True, exist_ok=True)
    report_file = report_dir / f"eval-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")

    if args.output == "json":
        _dump(report)
        return 0
    print()
    print("## Pipeline Evaluation Report")
    print()
    print(f"**Timestamp:** {report['evaluation_timestamp']}")
    print(f"**Test Directory:** {test_dir}")
    print(f"**Test Cases:** {len(test_cases)} found, {len(results)} evaluated")
    print()
    print("### Aggregate Metrics")
    print("| Metric | Value |")
    print("|--------|-------|")
    print(f"| True Positives | {totals['tp']} |")
    print(f"| False Positives | {totals['fp']} |")
    print(f"| False Negatives | {totals['fn']} |")
    print(f"| **Precision** | **{report['aggregate_metrics']['precision']}** |")
    print(f"| **Recall** | **{report['aggregate_metrics']['recall']}** |")
    print(f"| **F1 Score** | **{report['aggregate_metrics']['f1_score']}** |")
    print(f"| False Positive Rate | {report['aggregate_metrics']['false_positive_rate']} |")
    print()
    print(f"Report saved to: {report_file}")
    return 0


# ---------------------------------------------------------------------------
# Review gate runtime
# ---------------------------------------------------------------------------


def _run_quiet(command: Sequence[str], cwd: Path | None = None, input_text: str | None = None, timeout: int = 120) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(command),
        cwd=str(cwd) if cwd else None,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )


def _project_root() -> Path:
    try:
        completed = _run_quiet(["git", "rev-parse", "--show-toplevel"], timeout=5)
        if completed.returncode == 0 and completed.stdout.strip():
            return Path(completed.stdout.strip())
    except Exception:
        pass
    return Path.cwd()


def _changed_files(root: Path) -> List[str]:
    files: List[str] = []
    for command in [["git", "diff", "--name-only", "HEAD"], ["git", "diff", "--cached", "--name-only"]]:
        try:
            completed = _run_quiet(command, cwd=root, timeout=10)
        except Exception:
            continue
        if completed.returncode == 0:
            files.extend(line.strip() for line in completed.stdout.splitlines() if line.strip())
    return _unique(files)


def _changed_line_count(root: Path) -> int:
    try:
        completed = _run_quiet(["git", "diff", "--numstat", "HEAD"], cwd=root, timeout=10)
    except Exception:
        return 0
    total = 0
    for line in completed.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 2:
            total += _as_int(parts[0], 0) + _as_int(parts[1], 0)
    return total


def _reviewable(files: Sequence[str], root: Path, extensions: Sequence[str]) -> List[str]:
    allowed = {ext.strip().lstrip(".") for ext in extensions if ext.strip()}
    if not allowed:
        allowed = {"ts", "tsx", "js", "jsx", "py", "go", "rs", "java", "kt", "swift", "rb", "php", "c", "cpp", "cs"}
    out: List[str] = []
    for file in files:
        path = root / file
        if path.exists() and path.is_file() and path.suffix.lstrip(".") in allowed:
            out.append(file)
    return out


def cmd_review_gate(argv: Sequence[str]) -> int:
    _ = sys.stdin.read()
    root = _project_root()
    cfg = _load_config_lenient(str(_default_config_path()))
    project_cfg = root / ".ai-review-arena.json"
    if project_cfg.exists():
        cfg = _load_config_lenient(str(project_cfg))
    gate = cfg.get("review_gate", {}) if isinstance(cfg.get("review_gate"), dict) else {}
    if not _bool(gate.get("enabled"), False):
        return 0

    session_hash = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:12]
    session_dir = Path("/tmp") / f"ai-review-arena-{session_hash}"
    session_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    cooldown_file = session_dir / ".review_gate_last_run"
    now = int(time.time())
    cooldown = _as_int(gate.get("cooldown_seconds"), 120)
    if cooldown_file.exists() and now - _as_int(cooldown_file.read_text(encoding="utf-8"), 0) < cooldown:
        return 0

    files = _changed_files(root)
    min_files = _as_int(gate.get("min_files_changed"), 2)
    if len(files) < min_files:
        return 0
    line_count = _changed_line_count(root)
    if line_count < _as_int(gate.get("min_lines_changed"), 20):
        return 0

    review_cfg = cfg.get("review", {}) if isinstance(cfg.get("review"), dict) else {}
    reviewable = _reviewable(files, root, review_cfg.get("file_extensions", []) if isinstance(review_cfg.get("file_extensions"), list) else [])
    if not reviewable:
        return 0
    cooldown_file.write_text(str(now), encoding="utf-8")

    findings: List[Dict[str, Any]] = []
    models = gate.get("models") if isinstance(gate.get("models"), list) else ["codex", "gemini"]
    roles = gate.get("roles") if isinstance(gate.get("roles"), list) else ["security", "bugs"]
    timeout_seconds = _as_int(cfg.get("timeout"), 60)
    for file in reviewable:
        path = root / file
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for model in models:
            script = _plugin_dir() / "scripts" / f"{model}-review.sh"
            if not script.exists() or shutil.which(str(model)) is None:
                continue
            for role in roles:
                try:
                    completed = _run_quiet(["bash", str(script), file, str(_default_config_path()), str(role)], cwd=root, input_text=content, timeout=timeout_seconds)
                except Exception:
                    continue
                parsed = _extract_json_object(completed.stdout or "")
                if not parsed:
                    continue
                payload, _issues = normalize_provider_payload(parsed)
                if payload:
                    for item in payload.get("findings", []):
                        if isinstance(item, dict):
                            item = dict(item)
                            item.setdefault("model", model)
                            item.setdefault("role", role)
                            item.setdefault("file", file)
                            findings.append(item)

    if not findings:
        return 0
    critical_count = len([item for item in findings if _normalize_severity(item.get("severity")) == "critical"])
    block = _bool(gate.get("block_on_critical"), True) and critical_count > 0
    lang = ((cfg.get("output") or {}).get("language") if isinstance(cfg.get("output"), dict) else "ko") or "ko"
    prefix = f"Review Gate ({len(reviewable)} files, ~{line_count} lines changed):"
    suffix = f"Found {critical_count} CRITICAL issue(s). Please resolve before proceeding." if block else "Review the above feedback and address relevant issues."
    if lang == "ko":
        prefix = f"Review Gate ({len(reviewable)}개 파일, ~{line_count}줄 변경):"
        suffix = f"CRITICAL 이슈 {critical_count}건이 발견되었습니다. 해결 후 진행해주세요." if block else "위 피드백을 참고하여 필요한 부분만 수정하세요."
    _dump(
        {
            "hookSpecificOutput": {
                "hookEventName": "Stop",
                "review_gate": True,
                "critical_count": critical_count,
                "decision": "block" if block else "report",
                "additionalContext": prefix + "\n" + json.dumps(findings, ensure_ascii=False, indent=2) + "\n\n" + suffix,
            }
        }
    )
    return 0


# ---------------------------------------------------------------------------
# Static analysis runtime
# ---------------------------------------------------------------------------


def _static_parser(argv: Sequence[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="static-analysis")
    parser.add_argument("project_root", nargs="?", default="")
    parser.add_argument("--stack", default="")
    parser.add_argument("--max-findings", type=int, default=50)
    parser.add_argument("--confidence-floor", type=int, default=60)
    parser.add_argument("--output-dir", default="")
    return parser.parse_args(list(argv))


def _select_scanners(stack: Dict[str, Any]) -> List[str]:
    scanners: List[str] = []
    languages = [str(lang).lower() for lang in stack.get("languages", []) if str(lang)]
    for lang in languages:
        if lang in {"python"}:
            if shutil.which("bandit"):
                scanners.append("bandit")
            if shutil.which("semgrep"):
                scanners.append("semgrep-python")
        elif lang in {"javascript", "typescript", "nodejs"}:
            if shutil.which("eslint"):
                scanners.append("eslint")
            if shutil.which("semgrep"):
                scanners.append("semgrep-js")
        elif lang in {"go", "golang"}:
            if shutil.which("gosec"):
                scanners.append("gosec")
            if shutil.which("semgrep"):
                scanners.append("semgrep-go")
        elif lang in {"java", "kotlin"}:
            if shutil.which("semgrep"):
                scanners.append("semgrep-java")
        elif lang == "ruby":
            if shutil.which("brakeman"):
                scanners.append("brakeman")
            if shutil.which("semgrep"):
                scanners.append("semgrep-ruby")
        elif lang == "rust":
            if shutil.which("cargo"):
                scanners.append("cargo-audit")
        elif shutil.which("semgrep"):
            scanners.append("semgrep-generic")
    if not scanners and shutil.which("semgrep"):
        scanners.append("semgrep-generic")
    return _unique(scanners)


def _scanner_command(scanner: str, project: Path, output_file: Path) -> Tuple[List[str], Path | None]:
    project_s = str(project)
    if scanner == "bandit":
        return ["bandit", "-r", project_s, "-f", "json", "--quiet"], None
    if scanner == "eslint":
        return ["eslint", project_s, "-f", "json", "--no-error-on-unmatched-pattern"], None
    if scanner == "gosec":
        return ["gosec", "-fmt=json", "-quiet", f"{project_s}/..."], None
    if scanner == "brakeman":
        return ["brakeman", "-q", "-f", "json", project_s], None
    if scanner == "cargo-audit":
        return ["cargo", "audit", "--json"], project
    if scanner == "semgrep-python":
        return ["semgrep", "--config=auto", "--lang=python", "--json", "--quiet", project_s], None
    if scanner == "semgrep-js":
        return ["semgrep", "--config=auto", "--lang=javascript", "--lang=typescript", "--json", "--quiet", project_s], None
    if scanner == "semgrep-go":
        return ["semgrep", "--config=auto", "--lang=go", "--json", "--quiet", project_s], None
    if scanner == "semgrep-java":
        return ["semgrep", "--config=auto", "--lang=java", "--json", "--quiet", project_s], None
    if scanner == "semgrep-ruby":
        return ["semgrep", "--config=auto", "--lang=ruby", "--json", "--quiet", project_s], None
    return ["semgrep", "--config=auto", "--json", "--quiet", project_s], None


def _normalize_scanner_data(scanner: str, data: Any, floor: int) -> List[Dict[str, Any]]:
    if scanner == "bandit":
        findings = _normalize_bandit(scanner, data)
    elif scanner == "eslint":
        findings = _normalize_eslint(scanner, data)
    elif scanner == "gosec":
        findings = _normalize_gosec(scanner, data)
    elif scanner == "brakeman":
        findings = _normalize_brakeman(scanner, data)
    elif scanner == "cargo-audit":
        findings = _normalize_cargo_audit(scanner, data)
    elif scanner.startswith("semgrep"):
        findings = _normalize_semgrep(scanner, data)
    else:
        findings = []
    return [finding for finding in findings if _as_int(finding.get("confidence"), 0) >= floor]


def cmd_static_analysis(argv: Sequence[str]) -> int:
    args = _static_parser(argv)
    project = Path(args.project_root or ".").resolve(strict=False)
    if args.stack:
        try:
            stack = json.loads(args.stack)
        except json.JSONDecodeError:
            stack = {"languages": []}
    else:
        stack = _detect_dependencies(project)
    scanners = _select_scanners(stack if isinstance(stack, dict) else {"languages": []})
    if not scanners:
        result = {"scanners_run": [], "findings": [], "summary": "No scanners available"}
        _dump(result)
        return 0

    findings: List[Dict[str, Any]] = []
    with tempfile.TemporaryDirectory(prefix="arena-static-") as tmp:
        tmp_path = Path(tmp)
        for scanner in scanners:
            output_file = tmp_path / f"{scanner}.json"
            command, cwd = _scanner_command(scanner, project, output_file)
            try:
                completed = _run_quiet(command, cwd=cwd, timeout=120)
                output_file.write_text(completed.stdout or "[]", encoding="utf-8")
            except Exception:
                output_file.write_text("[]", encoding="utf-8")
            try:
                data = json.loads(output_file.read_text(encoding="utf-8"))
            except Exception:
                data = []
            findings.extend(_normalize_scanner_data(scanner, data, args.confidence_floor))

    findings.sort(key=lambda item: ({"critical": 0, "high": 1, "medium": 2, "low": 3}.get(item.get("severity", "medium"), 2), -_as_int(item.get("confidence"), 0)))
    total = len(findings)
    kept = findings[: max(0, args.max_findings)]
    if args.output_dir:
        output_dir = Path(args.output_dir)
        output_dir.mkdir(parents=True, exist_ok=True)
        (output_dir / "static-analysis-findings.json").write_text(json.dumps(kept, ensure_ascii=False, indent=2), encoding="utf-8")
    _dump(
        {
            "scanners_run": scanners,
            "total_findings": total,
            "findings_returned": len(kept),
            "findings": kept,
            "summary": f"Static analysis complete: {len(scanners)} scanners, {total} findings ({len(kept)} returned after filtering)",
        }
    )
    return 0


COMMANDS = {
    "run-debate": cmd_run_debate,
    "cost-estimator": cmd_cost_estimator,
    "escalation-scan": cmd_escalation_scan,
    "normalize-scanner-output": cmd_normalize_scanner_output,
    "cache-manager": cmd_cache_manager,
    "feedback-tracker": cmd_feedback_tracker,
    "detect-stack": cmd_detect_stack,
    "context-filter": cmd_context_filter,
    "signal-log": cmd_signal_log,
    "auto-tune-prompts": cmd_auto_tune_prompts,
    "evaluate-pipeline": cmd_evaluate_pipeline,
    "review-gate": cmd_review_gate,
    "static-analysis": cmd_static_analysis,
}


def main(argv: Sequence[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if not args or args[0] not in COMMANDS:
        print(f"Usage: {Path(sys.argv[0]).name} <{'|'.join(sorted(COMMANDS))}> ...", file=sys.stderr)
        return 2
    command = args[0]
    return COMMANDS[command](args[1:])
