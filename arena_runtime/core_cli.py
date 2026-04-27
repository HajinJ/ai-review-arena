from __future__ import annotations

import argparse
import json
import os
import shlex
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List

from .harness import HarnessRun
from .schemas import normalize_provider_payload, validate_provider_payload

SEVERITY_RANK = {"low": 1, "medium": 2, "high": 3, "critical": 4}


def normalize_severity(value: str | None) -> str:
    key = (value or "medium").lower()
    if key in {"error", "critical", "blocker", "fatal"}:
        return "critical"
    if key in {"warning", "major", "high", "important"}:
        return "high"
    if key in {"info", "minor", "medium", "moderate", "note"}:
        return "medium"
    if key in {"hint", "trivial", "low", "suggestion", "style"}:
        return "low"
    return "medium"


def cmd_normalize_severity(_: argparse.Namespace) -> int:
    raw = sys.stdin.read()
    if not raw:
        return 0
    data = json.loads(raw)

    def norm(item: Any) -> Any:
        if isinstance(item, dict) and "severity" in item:
            item = dict(item)
            item["severity"] = normalize_severity(item.get("severity"))
        return item

    if isinstance(data, list):
        data = [norm(item) for item in data]
    else:
        data = norm(data)
    print(json.dumps(data, ensure_ascii=False, indent=2))
    return 0


def load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _int_in_range(value: Any, minimum: int, maximum: int) -> bool:
    try:
        parsed = int(value)
    except (TypeError, ValueError):
        return False
    return minimum <= parsed <= maximum


def cmd_validate_config(args: argparse.Namespace) -> int:
    path = Path(args.config_file)
    errors: List[str] = []
    if not path.exists():
        print(f"[arena:error] Config file not found: {path}", file=sys.stderr)
        return 1
    try:
        cfg = load_json(path)
    except Exception:
        print(f"[arena:error] Invalid JSON: {path}", file=sys.stderr)
        return 1
    for key in ["models", "review", "debate", "output"]:
        if key not in cfg:
            errors.append(f"Missing required key: {key}")
    max_review = cfg.get("cost_estimation", {}).get("max_per_review_dollars")
    if max_review is not None and not (0 < float(max_review) <= 1000):
        errors.append(f"max_per_review_dollars out of range (0-1000): {max_review}")
    threshold = cfg.get("review", {}).get("confidence_threshold")
    if threshold is not None and not (0 <= float(threshold) <= 100):
        errors.append(f"confidence_threshold out of range (0-100): {threshold}")
    runtime_root = cfg.get("runtime", {})
    runtime_cli = runtime_root.get("cli", {}) if isinstance(runtime_root, dict) else {}
    if runtime_cli and not isinstance(runtime_cli, dict):
        errors.append("runtime.cli must be an object")
        runtime_cli = {}
    if runtime_cli:
        allowlist = runtime_cli.get("allowlist", [])
        if not isinstance(allowlist, list) or not all(isinstance(item, str) and item for item in allowlist):
            errors.append("runtime.cli.allowlist must be a non-empty string array when configured")
        default_timeout = runtime_cli.get("default_timeout_seconds", 120)
        if not _int_in_range(default_timeout, 1, 3600):
            errors.append(f"runtime.cli.default_timeout_seconds out of range (1-3600): {default_timeout}")
        if runtime_cli.get("deny_shell") is not True:
            errors.append("runtime.cli.deny_shell must be true")
    models_cfg = cfg.get("models", {})
    if models_cfg is not None and not isinstance(models_cfg, dict):
        errors.append("models must be an object")
        models_cfg = {}
    for provider, model_cfg in models_cfg.items():
        if not isinstance(model_cfg, dict):
            continue
        command = model_cfg.get("command")
        if command:
            try:
                parsed = shlex.split(str(command))
            except ValueError as exc:
                errors.append(f"models.{provider}.command is not shell-parseable: {exc}")
                continue
            if runtime_cli.get("allowlist") and parsed and Path(parsed[0]).name not in set(runtime_cli.get("allowlist", [])):
                errors.append(f"models.{provider}.command executable is not runtime allowlisted: {parsed[0]}")
            timeout = model_cfg.get("timeout_seconds", runtime_cli.get("default_timeout_seconds", 120))
            if not _int_in_range(timeout, 1, 3600):
                errors.append(f"models.{provider}.timeout_seconds out of range (1-3600): {timeout}")
    for error in errors:
        print(f"[arena:error] {error}", file=sys.stderr)
    if errors:
        print(f"[arena:error] Config validation failed with {len(errors)} error(s)", file=sys.stderr)
        return 1
    print(f"[arena:info] Config validation passed: {path}", file=sys.stderr)
    return 0


def cmd_aggregate_findings(args: argparse.Namespace) -> int:
    session_dir = Path(args.session_dir)
    harness = HarnessRun.from_env(session_dir.resolve())
    harness.emit("aggregation.started", phase="aggregation", session_dir=str(session_dir))
    cfg = load_json(Path(args.config_file)) if args.config_file and Path(args.config_file).exists() else {}
    threshold = int(cfg.get("review", {}).get("confidence_threshold", 40))
    merged: List[Dict[str, Any]] = []
    for file in sorted(session_dir.glob("findings_*.json")):
        try:
            data = load_json(file)
        except Exception:
            continue
        payload, _issues = normalize_provider_payload(data)
        if not payload:
            continue
        model = payload.get("model", "unknown")
        role = payload.get("role", "unknown")
        src_file = payload.get("file", "")
        for finding in payload.get("findings", []):
            if not isinstance(finding, dict) or not finding.get("title"):
                continue
            item = dict(finding)
            item["severity"] = normalize_severity(item.get("severity"))
            item.setdefault("confidence", 50)
            item.setdefault("file", src_file)
            item["model"] = model
            item["role"] = role
            item["models"] = [model]
            merged.append(item)
    if not merged:
        harness.emit("aggregation.completed", phase="aggregation", finding_count=0, output="LGTM")
        print("LGTM")
        return 0
    clusters: List[List[Dict[str, Any]]] = []
    for finding in merged:
        match = None
        for idx, cluster in enumerate(clusters):
            prev = cluster[-1]
            if prev.get("file") == finding.get("file") and abs(int(prev.get("line", 0) or 0) - int(finding.get("line", 0) or 0)) <= 3 and _similar_title(str(prev.get("title", "")), str(finding.get("title", ""))):
                match = idx
                break
        if match is None:
            clusters.append([finding])
        else:
            clusters[match].append(finding)
    aggregated = [_aggregate_cluster(cluster) for cluster in clusters]
    aggregated = [item for item in aggregated if _passes_threshold(item, threshold)]
    if not aggregated:
        harness.emit("aggregation.completed", phase="aggregation", finding_count=0, output="LGTM")
        print("LGTM")
        return 0
    aggregated.sort(key=lambda item: -(int(item.get("confidence", 0)) * 10 + SEVERITY_RANK.get(item.get("severity", "medium"), 0) * 100))
    harness.emit("aggregation.completed", phase="aggregation", finding_count=len(aggregated))
    print(json.dumps(aggregated, ensure_ascii=False, indent=2))
    return 0


def _similar_title(left: str, right: str) -> bool:
    l_words = left.lower().split()
    r_words = right.lower().split()
    n = min(len(l_words), len(r_words), 3)
    return n > 0 and l_words[:n] == r_words[:n]


def _aggregate_cluster(cluster: List[Dict[str, Any]]) -> Dict[str, Any]:
    if len(cluster) == 1:
        item = dict(cluster[0])
        item["line"] = int(item.get("line", 0) or 0)
        item["cross_model_agreement"] = False
        item.setdefault("description", "")
        item.setdefault("suggestion", "")
        return {k: item.get(k) for k in ["file", "line", "title", "description", "suggestion", "severity", "confidence", "models", "role", "cross_model_agreement"]}
    models = sorted({str(item.get("model", "unknown")) for item in cluster})
    severity = max((normalize_severity(item.get("severity")) for item in cluster), key=lambda sev: SEVERITY_RANK.get(sev, 0))
    confidence = min(100, int(sum(int(item.get("confidence", 50) or 50) for item in cluster) / len(cluster)) + 15)
    first = cluster[0]
    return {
        "file": first.get("file", ""),
        "line": min(int(item.get("line", 0) or 0) for item in cluster),
        "title": first.get("title", "Untitled"),
        "description": next((str(item.get("description")) for item in cluster if item.get("description")), ""),
        "suggestion": next((str(item.get("suggestion")) for item in cluster if item.get("suggestion")), ""),
        "severity": severity,
        "confidence": confidence,
        "models": models,
        "role": first.get("role", "unknown"),
        "cross_model_agreement": len(models) > 1,
    }


def _passes_threshold(item: Dict[str, Any], threshold: int) -> bool:
    conf = int(item.get("confidence", 0) or 0)
    sev = item.get("severity", "medium")
    if sev == "critical":
        return conf >= threshold - 30
    if sev == "high":
        return conf >= threshold - 15
    if sev == "medium":
        return conf >= threshold
    if sev == "low":
        return conf >= threshold + 10
    return conf >= threshold


def cmd_generate_report(args: argparse.Namespace) -> int:
    harness = HarnessRun.from_env()
    harness.emit("report.started", phase="report", consensus_file=str(args.consensus_file))
    cfg = load_json(Path(args.config_file)) if args.config_file and Path(args.config_file).exists() else {}
    raw = sys.stdin.read() if args.consensus_file in {"-", "/dev/stdin"} else Path(args.consensus_file).read_text(encoding="utf-8")
    if not raw or raw.strip() == "null":
        print("LGTM")
        return 0
    data = json.loads(raw)
    if isinstance(data, dict) and "accepted" in data:
        accepted = data.get("accepted", []) or []
        rejected = data.get("rejected", []) or []
        disputed = data.get("disputed", []) or []
        findings = accepted + disputed
    elif isinstance(data, list):
        accepted = data
        rejected = []
        disputed = []
        findings = data
    else:
        print("LGTM")
        return 0
    if not findings:
        print("LGTM")
        return 0
    lang = cfg.get("output", {}).get("language", "ko")
    confidence_label = "신뢰도" if lang == "ko" else "Confidence"
    suggestion_label = "제안" if lang == "ko" else "Suggestion"
    agreement_label = "교차 모델 합의" if lang == "ko" else "Cross-model agreement"
    evidence_label = "근거" if lang == "ko" else "Evidence"
    title = "## AI Review Arena Report"
    print(title)
    print()
    models = sorted({m for item in findings for m in item.get("models", [])})
    print(f"Models: {', '.join(models) if models else 'unknown'} | Intensity: {cfg.get('review', {}).get('intensity', 'standard')} | Focus: {', '.join(cfg.get('review', {}).get('focus_areas', [])) or 'all'}")
    print(f"Files: {len({item.get('file') for item in findings})} | Findings: {len(accepted)} accepted, {len(rejected)} rejected, {len(disputed)} disputed")
    print()
    for sev in ["critical", "high", "medium", "low"]:
        bucket = [item for item in findings if item.get("severity") == sev]
        if not bucket:
            continue
        print(f"### {sev.upper()}")
        print()
        for idx, item in enumerate(bucket, 1):
            print(f"{idx}. **{Path(str(item.get('file', '?'))).name}:{item.get('line', '?')}** - {item.get('title', 'Untitled')}")
            print(f"   {confidence_label}: {item.get('confidence', '?')}%")
            if item.get("description"):
                print(f"   {item.get('description')}")
            if item.get("suggestion"):
                print(f"   {suggestion_label}: {item.get('suggestion')}")
            if item.get("cross_model_agreement"):
                print(f"   {agreement_label}")
            evidence_chunks = item.get("evidence_chunks", []) if isinstance(item.get("evidence_chunks"), list) else []
            if evidence_chunks:
                print(f"   {evidence_label}:")
                for chunk in evidence_chunks[:3]:
                    if not isinstance(chunk, dict):
                        continue
                    boundary = chunk.get("boundary", {}) if isinstance(chunk.get("boundary"), dict) else {}
                    flags = boundary.get("flags", []) if isinstance(boundary.get("flags"), list) else []
                    location = f"{chunk.get('file', '?')}#chunk-{chunk.get('chunk_id', '?')}"
                    print(f"   - {chunk.get('id', 'evidence')}: {location} score={chunk.get('score', '?')} flags={','.join(str(flag) for flag in flags) if flags else 'none'}")
            print()
    if disputed:
        print("### DISPUTED (manual review needed)")
    harness.emit("report.completed", phase="report", finding_count=len(findings), accepted=len(accepted), rejected=len(rejected), disputed=len(disputed))
    return 0


def cmd_validate_provider_output(args: argparse.Namespace) -> int:
    raw = sys.stdin.read() if args.provider_output in {"-", "/dev/stdin"} else Path(args.provider_output).read_text(encoding="utf-8")
    try:
        payload = json.loads(raw)
    except Exception as exc:
        print(f"[arena:error] invalid provider JSON: {exc}", file=sys.stderr)
        return 1
    issues = validate_provider_payload(payload)
    if issues:
        for issue in issues:
            print(f"[arena:error] {issue.path}: {issue.message}", file=sys.stderr)
        return 1
    print("[arena:info] Provider output validation passed", file=sys.stderr)
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="arena-runtime")
    sub = parser.add_subparsers(dest="command")

    p = sub.add_parser("normalize-severity")
    p.set_defaults(func=cmd_normalize_severity)

    p = sub.add_parser("validate-config")
    p.add_argument("config_file")
    p.set_defaults(func=cmd_validate_config)

    p = sub.add_parser("aggregate-findings")
    p.add_argument("session_dir")
    p.add_argument("config_file", nargs="?")
    p.set_defaults(func=cmd_aggregate_findings)

    p = sub.add_parser("generate-report")
    p.add_argument("consensus_file")
    p.add_argument("config_file", nargs="?")
    p.set_defaults(func=cmd_generate_report)

    p = sub.add_parser("validate-provider-output")
    p.add_argument("provider_output")
    p.set_defaults(func=cmd_validate_provider_output)
    return parser


def main(argv: List[str] | None = None) -> int | None:
    parser = build_parser()
    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        return 2
    return args.func(args)
