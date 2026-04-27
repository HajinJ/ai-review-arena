from __future__ import annotations

import argparse
import concurrent.futures
import fnmatch
import hashlib
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence

from .rag_runtime import build_index_chunks, extract_imports, extract_symbols, token_counts

DOC_CATEGORIES = {"accuracy", "completeness", "freshness", "readability", "examples", "consistency"}
BUSINESS_CATEGORIES = {"accuracy", "audience", "positioning", "clarity", "evidence"}
ROLE_KEYWORDS = {
    "security": "authentication authorization validation injection xss csrf encryption token secret credential",
    "security-reviewer": "authentication authorization validation injection xss csrf encryption token secret credential",
    "bugs": "error null undefined race condition exception concurrency async await",
    "bug-detector": "error null undefined race condition exception concurrency async await",
    "performance": "cache latency query n+1 allocation memory algorithm complexity",
    "performance-reviewer": "cache latency query n+1 allocation memory algorithm complexity",
    "architecture": "module dependency coupling cohesion interface abstraction service layer",
    "architecture-reviewer": "module dependency coupling cohesion interface abstraction service layer",
    "testing": "test assert mock fixture coverage unit integration e2e",
    "test-coverage-reviewer": "test assert mock fixture coverage unit integration e2e",
}
SCRIPT_CLASS_ALLOW_SUPPORT: set[str] = set()
DOMAIN_BENCHMARK_PROFILES = {
    "smoke": {"timeout_seconds": 10, "max_cases": 1, "max_parallel": 2},
    "standard": {"timeout_seconds": 15, "max_cases": 2, "max_parallel": 4},
    "calibration": {"timeout_seconds": 30, "max_cases": 6, "max_parallel": 4},
    "full": {"timeout_seconds": 60, "max_cases": 0, "max_parallel": 4},
}


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _load_json_safe(path: Path) -> Dict[str, Any]:
    try:
        data = _load_json(path)
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


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


def _extract_json(text: str) -> Dict[str, Any] | None:
    stripped = (text or "").strip()
    if not stripped:
        return None
    try:
        data = json.loads(stripped)
        if isinstance(data, dict):
            return _coerce_payload(data)
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
            return _coerce_payload(data)
    return None


def _coerce_payload(data: Dict[str, Any]) -> Dict[str, Any]:
    if isinstance(data.get("findings"), list) or isinstance(data.get("responses"), list):
        return data
    for key in ("response", "text", "content", "message", "output"):
        value = data.get(key)
        if isinstance(value, dict):
            nested = _coerce_payload(value)
            if isinstance(nested.get("findings"), list) or isinstance(nested.get("responses"), list):
                return nested
        if isinstance(value, str):
            nested = _extract_json(value)
            if nested and (isinstance(nested.get("findings"), list) or isinstance(nested.get("responses"), list)):
                return nested
    return data


def _run(command: Sequence[str], input_text: str | None, timeout: int) -> subprocess.CompletedProcess[str]:
    proc = subprocess.Popen(
        list(command),
        stdin=subprocess.PIPE if input_text is not None else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        start_new_session=True,
    )
    try:
        stdout, stderr = proc.communicate(input=input_text, timeout=max(1, timeout))
        return subprocess.CompletedProcess(list(command), proc.returncode, stdout, stderr)
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
        return subprocess.CompletedProcess(list(command), 124, stdout or "", stderr or f"Timed out after {timeout}s")


def _model_cfg(cfg: Dict[str, Any], provider: str) -> Dict[str, Any]:
    models = cfg.get("models", {}) if isinstance(cfg.get("models"), dict) else {}
    return models.get(provider, {}) if isinstance(models.get(provider), dict) else {}


def _provider_variant(cfg: Dict[str, Any], provider: str) -> str:
    provider_cfg = _model_cfg(cfg, provider)
    root_cfg = cfg.get(provider, {}) if isinstance(cfg.get(provider), dict) else {}
    return str(provider_cfg.get("model_variant", root_cfg.get("model_variant", "")) or "")


def _use_user_default(cfg: Dict[str, Any], provider: str) -> bool:
    provider_cfg = _model_cfg(cfg, provider)
    root_cfg = cfg.get(provider, {}) if isinstance(cfg.get(provider), dict) else {}
    return _bool(provider_cfg.get("use_user_default", root_cfg.get("use_user_default", True)), True)


def _timeout(cfg: Dict[str, Any], mode: str, explicit: int = 0) -> int:
    if explicit > 0:
        return explicit
    fallback = cfg.get("fallback", {}) if isinstance(cfg.get("fallback"), dict) else {}
    key = "external_cli_debate_timeout_seconds" if mode == "round2" else "external_cli_timeout_seconds"
    return max(1, min(300, _as_int(fallback.get(key, cfg.get("timeout", 120)), 120)))


def _category_set(domain: str) -> set[str]:
    return DOC_CATEGORIES if domain == "doc" else BUSINESS_CATEGORIES


def _review_prompt(domain: str, provider: str, mode: str, category: str, content: str) -> str:
    domain_label = "documentation" if domain == "doc" else "business content"
    role_prefix = "doc-" if domain == "doc" else "business-"
    categories = {
        "accuracy": "factual correctness, API/signature alignment, data accuracy, and claim validation",
        "completeness": "coverage gaps, missing parameters, missing setup steps, and undocumented behavior",
        "freshness": "deprecated references, stale versions, removed features, and outdated prerequisites",
        "readability": "structure, progressive disclosure, audience fit, jargon, and cognitive load",
        "examples": "runnable examples, imports, outputs, insecure snippets, and deprecated patterns",
        "consistency": "terminology, cross references, naming, style, and tone consistency",
        "audience": "target reader fit, tone, complexity, relevance, and engagement",
        "positioning": "value proposition, differentiation, competitive positioning, and market clarity",
        "clarity": "ambiguity, structure, flow, redundancy, and vague language",
        "evidence": "source credibility, data quality, evidence strength, and unsupported assertions",
    }
    if mode == "round2":
        return f"""You are a rigorous {domain_label} cross-reviewer.
Review other models' findings and return valid JSON only.

Return this shape:
{{
  "model": "{provider}",
  "role": "{role_prefix}cross-review",
  "mode": "round2",
  "responses": [
    {{"finding_id": "id", "action": "challenge|support", "confidence_adjustment": 0, "reasoning": "specific reason"}}
  ]
}}

Input:
{content}
"""
    return f"""You are a {domain_label} reviewer specializing in {category}.
Focus only on: {categories.get(category, category)}.
Return valid JSON only. Do not wrap in markdown.

Return this shape:
{{
  "model": "{provider}",
  "role": "{role_prefix}{category}",
  "mode": "round1",
  "findings": [
    {{
      "severity": "critical|high|medium|low",
      "confidence": 0,
      "section": "section or location",
      "title": "brief title",
      "category": "{category}",
      "description": "detailed explanation",
      "suggestion": "specific fix"
    }}
  ],
  "summary": "2-3 sentence assessment"
}}

Content:
{content}
"""


def _provider_command(provider: str, cfg: Dict[str, Any], prompt: str) -> tuple[list[str], str | None]:
    variant = _provider_variant(cfg, provider)
    if provider == "codex":
        command = ["codex", "exec", "--skip-git-repo-check", "--ephemeral", "--ignore-rules", "--color", "never", "--sandbox", "read-only", "-"]
        if not _use_user_default(cfg, provider) and variant:
            command[2:2] = ["-m", variant]
        return command, prompt
    command = ["gemini", "--output-format", "json", "--approval-mode", "plan", "--prompt", prompt]
    if not _use_user_default(cfg, provider) and variant:
        command[1:1] = ["--model", variant]
    return command, None


def _normalize_review(domain: str, provider: str, mode: str, category: str, parsed: Dict[str, Any], error: str = "") -> Dict[str, Any]:
    role_prefix = "doc-" if domain == "doc" else "business-"
    role = f"{role_prefix}{category}" if mode == "round1" else f"{role_prefix}cross-review"
    result: Dict[str, Any] = {"model": provider, "role": role, "mode": mode}
    if error:
        result["error"] = error
    if mode == "round2":
        responses = parsed.get("responses", []) if isinstance(parsed.get("responses"), list) else []
        result["responses"] = [item for item in responses if isinstance(item, dict)]
        return result
    findings = parsed.get("findings", []) if isinstance(parsed.get("findings"), list) else []
    normalized = []
    for item in findings:
        if not isinstance(item, dict):
            continue
        row = dict(item)
        row["severity"] = str(row.get("severity") or "medium").lower()
        if row["severity"] not in {"critical", "high", "medium", "low"}:
            row["severity"] = "medium"
        row["confidence"] = max(0, min(100, _as_int(row.get("confidence"), 50)))
        row.setdefault("category", category)
        row.setdefault("title", str(row.get("description") or "Finding")[:80])
        row.setdefault("description", "")
        row.setdefault("suggestion", "")
        normalized.append(row)
    result["findings"] = normalized
    result["summary"] = str(parsed.get("summary") or "No summary provided")
    return result


def cmd_content_review(domain: str, provider: str, argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog=f"{provider}-{domain}-review")
    parser.add_argument("config_file")
    parser.add_argument("--mode", required=True, choices=["round1", "round2"])
    parser.add_argument("--category", default="")
    parser.add_argument("--timeout", type=int, default=0)
    args = parser.parse_args(list(argv))

    categories = _category_set(domain)
    if args.mode == "round1" and args.category not in categories:
        _dump(_normalize_review(domain, provider, args.mode, args.category, {}, f"Invalid category: {args.category}. Must be one of: {', '.join(sorted(categories))}"))
        return 1
    if not shutil.which(provider):
        _dump(_normalize_review(domain, provider, args.mode, args.category, {}, f"{provider} CLI unavailable"))
        return 1
    content = sys.stdin.read()
    if not content.strip():
        _dump(_normalize_review(domain, provider, args.mode, args.category, {}, "No content provided on stdin"))
        return 1

    cfg = _load_json_safe(Path(args.config_file))
    timeout = _timeout(cfg, args.mode, args.timeout)
    prompt = _review_prompt(domain, provider, args.mode, args.category, content)
    command, input_text = _provider_command(provider, cfg, prompt)
    started = time.monotonic()
    completed = _run(command, input_text, timeout)
    latency_ms = int((time.monotonic() - started) * 1000)
    if completed.returncode == 124:
        result = _normalize_review(domain, provider, args.mode, args.category, {}, f"{provider} {domain} review timed out after {timeout}s")
        result["latency_ms"] = latency_ms
        _dump(result)
        return 0
    parsed = _extract_json(completed.stdout or "")
    if not parsed:
        result = _normalize_review(domain, provider, args.mode, args.category, {}, f"Failed to parse JSON from {provider} response")
        result["latency_ms"] = latency_ms
        _dump(result)
        return 0
    result = _normalize_review(domain, provider, args.mode, args.category, parsed)
    result["latency_ms"] = latency_ms
    _dump(result)
    return 0


def _benchmark_files(domain: str, category: str) -> List[Path]:
    root = _repo_root() / "config" / "benchmarks"
    prefix = "doc" if domain == "doc" else "business"
    if category == "all":
        return sorted(root.glob(f"{prefix}-*.json"))
    return sorted(root.glob(f"{prefix}-{category}-*.json"))


def _truths(case: Dict[str, Any]) -> List[Dict[str, Any]]:
    value = case.get("ground_truth", [])
    if isinstance(value, dict):
        return [value]
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def _findings(payload: Any) -> List[Dict[str, Any]]:
    if isinstance(payload, dict) and isinstance(payload.get("findings"), list):
        return [item for item in payload["findings"] if isinstance(item, dict)]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def _text(value: Dict[str, Any]) -> str:
    return " ".join(str(value.get(key) or "") for key in ["title", "section", "category", "type", "description", "suggestion"])


def _match_domain_finding(finding: Dict[str, Any], truth: Dict[str, Any]) -> bool:
    text = _text(finding).lower()
    section = str(truth.get("section") or "").lower()
    if section and section not in text:
        return False
    keywords = truth.get("description_contains", [])
    if isinstance(keywords, str):
        keywords = [keywords]
    if not isinstance(keywords, list) or not keywords:
        return bool(section)
    hits = sum(1 for keyword in keywords if str(keyword).lower() in text)
    return hits > len(keywords) / 2


def _score_domain(payload: Any, case: Dict[str, Any]) -> Dict[str, Any]:
    findings = _findings(payload)
    truths = _truths(case)
    matched_findings: set[int] = set()
    matched_truths = 0
    for truth in truths:
        match_index = None
        for idx, finding in enumerate(findings):
            if idx not in matched_findings and _match_domain_finding(finding, truth):
                match_index = idx
                break
        if match_index is not None:
            matched_truths += 1
            matched_findings.add(match_index)
    tp = matched_truths
    fp = max(0, len(findings) - len(matched_findings))
    fn = max(0, len(truths) - tp)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall else 0.0
    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1_score": round(f1, 3),
        "total_expected": len(truths),
        "total_actual": len(findings),
    }


def _aggregate(rows: Sequence[Dict[str, Any]]) -> Dict[str, Any]:
    tp = sum(_as_int(row.get("true_positives"), 0) for row in rows)
    fp = sum(_as_int(row.get("false_positives"), 0) for row in rows)
    fn = sum(_as_int(row.get("false_negatives"), 0) for row in rows)
    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall else 0.0
    return {"true_positives": tp, "false_positives": fp, "false_negatives": fn, "precision": round(precision, 3), "recall": round(recall, 3), "f1_score": round(f1, 3)}


def cmd_domain_benchmark(domain: str, argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog=f"benchmark-{domain}-models")
    parser.add_argument("--category", default="all")
    parser.add_argument("--models", default="codex,gemini,claude")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--profile", choices=["smoke", "standard", "full", "calibration"], default="standard")
    parser.add_argument("--max-cases", type=int, default=-1)
    parser.add_argument("--timeout", type=int, default=0)
    parser.add_argument("--max-parallel", type=int, default=4)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(list(argv))

    profile = DOMAIN_BENCHMARK_PROFILES[args.profile]
    max_cases = args.max_cases if args.max_cases >= 0 else int(profile["max_cases"])
    live = bool(args.live or args.profile == "full") and not (_bool(os.environ.get("CI"), False) and not args.live)
    models = [item.strip() for item in args.models.split(",") if item.strip()]
    files = _benchmark_files(domain, args.category)
    cases: List[tuple[Path, Dict[str, Any]]] = []
    for file in files:
        data = _load_json_safe(file)
        if data:
            cases.append((file, data))
        if max_cases > 0 and len(cases) >= max_cases:
            break

    cfg = _load_json_safe(Path(args.config))
    timeout = args.timeout if args.timeout > 0 else int(profile["timeout_seconds"])
    scores: Dict[str, List[Dict[str, Any]]] = {model: [] for model in models}
    provider_status: Dict[str, Dict[str, Any]] = {}

    def skipped(model: str, case_file: Path, case: Dict[str, Any], status: str, reason: str) -> Dict[str, Any]:
        row = _score_domain({"findings": []}, case)
        row.update({"test_id": case.get("id", case_file.stem), "category": case.get("category", "unknown"), "status": status, "skipped": True, "reason": reason})
        return row

    def run_case(model: str, item: tuple[Path, Dict[str, Any]]) -> tuple[str, Dict[str, Any]]:
        case_file, case = item
        if model == "claude":
            return model, skipped(model, case_file, case, "manual_required", "Claude benchmark cases are emitted for orchestrator/agent execution")
        if model not in {"codex", "gemini"}:
            return model, skipped(model, case_file, case, "unsupported_model", f"Unsupported model: {model}")
        if not live:
            return model, skipped(model, case_file, case, "live_disabled", "Pass --live or --profile full to call external CLIs")
        if not shutil.which(model):
            return model, skipped(model, case_file, case, "model_unavailable", f"{model} CLI unavailable")
        prompt_content = str(case.get("content") or "")
        if case.get("source_code"):
            prompt_content += "\n\n--- RELATED SOURCE ---\n" + str(case.get("source_code"))
        prompt = _review_prompt(domain, model, "round1", str(case.get("category") or "accuracy"), prompt_content)
        command, input_text = _provider_command(model, cfg, prompt)
        completed = _run(command, input_text, timeout)
        if completed.returncode == 124:
            return model, skipped(model, case_file, case, "review_timeout", f"{model} timed out after {timeout}s")
        parsed = _extract_json(completed.stdout or "")
        if not parsed:
            return model, skipped(model, case_file, case, "parse_error", f"{model} returned invalid JSON")
        row = _score_domain(parsed, case)
        row.update({"test_id": case.get("id", case_file.stem), "category": case.get("category", "unknown"), "status": "scored", "skipped": False})
        return model, row

    for model in models:
        provider_status[model] = {"live": live, "available": shutil.which(model) is not None if model in {"codex", "gemini"} else False}

    futures: List[concurrent.futures.Future[tuple[str, Dict[str, Any]]]] = []
    max_parallel = max(1, min(16, args.max_parallel if args.max_parallel > 0 else int(profile["max_parallel"])))
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_parallel) as pool:
        for item in cases:
            for model in models:
                futures.append(pool.submit(run_case, model, item))
        for future in concurrent.futures.as_completed(futures):
            model, row = future.result()
            scores.setdefault(model, []).append(row)

    summary = {model: {**_aggregate(rows), "status_counts": _status_counts(rows)} for model, rows in scores.items()}
    output = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "domain": domain,
        "category": args.category,
        "profile": args.profile,
        "runtime": {"live": live, "timeout_seconds": timeout, "max_cases": max_cases, "cases_selected": len(cases), "max_parallel": max_parallel},
        "benchmark_files": [str(path) for path in files],
        "provider_status": provider_status,
        "scores": scores,
        "summary": summary,
    }
    _dump(output)
    return 0


def _status_counts(rows: Sequence[Dict[str, Any]]) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for row in rows:
        status = str(row.get("status") or "unknown")
        counts[status] = counts.get(status, 0) + 1
    return counts


def _project_hash(root: Path) -> str:
    return hashlib.sha256(str(root.resolve()).encode("utf-8")).hexdigest()[:16]


def _tokenize(text: str) -> set[str]:
    return {token.lower() for token in re.findall(r"[A-Za-z_][A-Za-z0-9_]{2,}", text)}


def _rag_cfg(config_file: str | None) -> Dict[str, Any]:
    cfg = _load_json_safe(Path(config_file)) if config_file else {}
    return cfg.get("rag", {}) if isinstance(cfg.get("rag"), dict) else {}


def _iter_index_files(root: Path, cfg: Dict[str, Any]) -> Iterable[Path]:
    exts = cfg.get("index_extensions") if isinstance(cfg.get("index_extensions"), list) else [".py", ".js", ".ts", ".tsx", ".java", ".go", ".rs"]
    exts = {str(ext if str(ext).startswith(".") else f".{ext}") for ext in exts}
    excludes = cfg.get("exclude_paths") if isinstance(cfg.get("exclude_paths"), list) else ["node_modules", ".git", "dist", "build", "__pycache__", ".venv"]
    max_files = max(1, _as_int(cfg.get("max_index_files"), 5000))
    count = 0
    for path in root.rglob("*"):
        if count >= max_files:
            break
        if not path.is_file() or path.suffix not in exts:
            continue
        rel = path.relative_to(root).as_posix()
        if any(part in rel.split("/") or fnmatch.fnmatch(rel, str(part)) for part in excludes):
            continue
        count += 1
        yield path


def _chunks(text: str, size: int, overlap: int) -> Iterable[str]:
    for chunk in build_index_chunks(text, "", chunk_size=size, overlap=overlap):
        content = str(chunk.get("content") or "")
        if content.strip():
            yield content


def cmd_rag_indexer(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="rag-indexer")
    parser.add_argument("project_root")
    parser.add_argument("--force", action="store_true")
    parser.add_argument("--config", default="")
    args = parser.parse_args(list(argv))
    root = Path(args.project_root).resolve()
    cfg = _rag_cfg(args.config)
    if not _bool(cfg.get("enabled"), True):
        _dump({"status": "disabled", "indexed_files": 0, "chunks": 0})
        return 0
    cache_dir = _repo_root() / "cache" / _project_hash(root) / "rag-index"
    cache_dir.mkdir(parents=True, exist_ok=True)
    index_file = cache_dir / "chunks.jsonl"
    chunk_size = max(20, _as_int(cfg.get("chunk_size"), 120))
    overlap = max(0, min(chunk_size - 1, _as_int(cfg.get("chunk_overlap"), 20)))
    indexed = 0
    chunk_count = 0
    with index_file.open("w", encoding="utf-8") as out:
        for path in _iter_index_files(root, cfg):
            try:
                text = path.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            indexed += 1
            rel = path.relative_to(root).as_posix()
            file_symbols = extract_symbols(text, rel)
            file_imports = extract_imports(text, rel)
            for idx, chunk_data in enumerate(build_index_chunks(text, rel, chunk_size=chunk_size, overlap=overlap)):
                chunk = str(chunk_data.get("content") or "")
                start_line = _as_int(chunk_data.get("start_line"), 0)
                end_line = _as_int(chunk_data.get("end_line"), 10**9)
                tokens = sorted(_tokenize(chunk))[:2000]
                row = {
                    "file": rel,
                    "chunk_id": idx,
                    "content": chunk,
                    "tokens": tokens,
                    "token_counts": token_counts(chunk),
                    "symbols": [symbol for symbol in file_symbols if start_line <= _as_int(symbol.get("line"), 0) <= end_line],
                    "imports": file_imports,
                    "type": chunk_data.get("type", "code"),
                    "start_line": start_line,
                    "end_line": end_line,
                    "embedding_model": cfg.get("embedding_model", "local-bm25-symbol-v1"),
                }
                out.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")) + "\n")
                chunk_count += 1
    _dump({"status": "indexed", "project_root": str(root), "index_dir": str(cache_dir), "indexed_files": indexed, "chunks": chunk_count})
    return 0


def cmd_rag_retrieve(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="rag-retrieve")
    parser.add_argument("project_root")
    parser.add_argument("role")
    parser.add_argument("query")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--config", default="")
    parser.add_argument("--rerank", action="store_true")
    args = parser.parse_args(list(argv))
    root = Path(args.project_root).resolve()
    cfg = _rag_cfg(args.config)
    if not _bool(cfg.get("enabled"), True):
        return 0
    index_file = _repo_root() / "cache" / _project_hash(root) / "rag-index" / "chunks.jsonl"
    if not index_file.exists():
        return 0
    query_tokens = _tokenize(args.query + " " + ROLE_KEYWORDS.get(args.role, ""))
    rows: List[Dict[str, Any]] = []
    with index_file.open("r", encoding="utf-8") as handle:
        for line in handle:
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                continue
            tokens = set(row.get("tokens", []))
            if not tokens:
                continue
            overlap = len(query_tokens & tokens)
            score = overlap / max(1, len(query_tokens))
            if score > 0:
                rows.append({"file": row.get("file"), "content": row.get("content"), "score": round(score, 4)})
    rows.sort(key=lambda item: item["score"], reverse=True)
    for row in rows[: max(1, args.top_k)]:
        print(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
    return 0


def cmd_validate_doc_consistency(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="validate-doc-consistency")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(list(argv))
    root = _repo_root()
    failures: List[str] = []
    retired = [
        "scripts/orchestrate-review.sh",
        "scripts/gemini-hook-adapter.sh",
        "scripts/openai-ws-debate.py",
        "scripts/stream-review.py",
        "scripts/check-model-updates.sh",
        "scripts/aggregate-findings.sh",
        "scripts/normalize-severity.sh",
        "scripts/generate-report.sh",
        "scripts/validate-config.sh",
    ]
    for rel in retired:
        if (root / rel).exists():
            failures.append(f"legacy entrypoint must not exist: {rel}")
    cfg = _load_json_safe(root / "config" / "default-config.json")
    for provider in ["claude", "codex", "gemini"]:
        if not _bool(_model_cfg(cfg, provider).get("use_user_default"), False):
            failures.append(f"models.{provider}.use_user_default must be true")
    if _bool((cfg.get("streaming", {}) or {}).get("enabled"), False):
        failures.append("streaming.enabled must stay false by default")
    if not _bool(((cfg.get("runtime", {}) or {}).get("cli", {}) or {}).get("deny_shell"), False):
        failures.append("runtime.cli.deny_shell must be true")
    if (cfg.get("runtime", {}) or {}).get("api"):
        failures.append("runtime.api must not exist in CLI-first runtime")
    scan_roots = ["README.md", "README.ko.md", "CLAUDE.md", "AGENTS.md", "docs", "commands", "config", ".codex", ".claude-plugin", "marketplace.json"]
    blocked_patterns = [
        "wss://api.openai",
        "openai-ws-debate",
        "stream-review.py",
        "check-model-updates",
    ]
    for rel in scan_roots:
        path = root / rel
        candidates = [path] if path.is_file() else list(path.rglob("*")) if path.is_dir() else []
        for candidate in candidates:
            if not candidate.is_file() or any(part in {"cache", "__pycache__"} for part in candidate.relative_to(root).parts):
                continue
            try:
                text = candidate.read_text(encoding="utf-8", errors="replace")
            except OSError:
                continue
            for pattern in blocked_patterns:
                if pattern in text and candidate.name != "validate-doc-consistency.sh":
                    failures.append(f"legacy non-CLI reference found: {candidate.relative_to(root)} contains {pattern}")
                    break
    for key in ["benchmarks", "business_benchmarks", "docs_benchmarks"]:
        section = cfg.get(key, {}) if isinstance(cfg.get(key), dict) else {}
        if _bool(section.get("auto_run"), False):
            failures.append(f"{key}.auto_run must be false")
        if not section.get("default_profile"):
            failures.append(f"{key}.default_profile is required")
    versions = []
    for rel, path_expr in [("marketplace.json", ["version"]), (".claude-plugin/plugin.json", ["version"]), (".claude-plugin/marketplace.json", ["plugins", 0, "version"] )]:
        data = _load_json_safe(root / rel)
        value: Any = data
        for part in path_expr:
            if isinstance(part, int) and isinstance(value, list) and len(value) > part:
                value = value[part]
            elif isinstance(part, str) and isinstance(value, dict):
                value = value.get(part)
            else:
                value = None
        if value:
            versions.append(str(value))
    if versions and len(set(versions)) > 1:
        failures.append(f"version mismatch: {versions}")
    result = {"status": "ok" if not failures else "failed", "failures": failures}
    if args.json:
        _dump(result)
    elif failures:
        for failure in failures:
            print(f"[doc-consistency] FAIL: {failure}", file=sys.stderr)
    else:
        print("[doc-consistency] OK")
    return 1 if failures else 0


def cmd_legacy_inventory(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="legacy-inventory")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(list(argv))
    scripts = sorted((_repo_root() / "scripts").glob("*.sh"))
    rows: List[Dict[str, Any]] = []
    for path in scripts:
        text = path.read_text(encoding="utf-8", errors="replace")
        lines = text.splitlines()
        is_wrapper = "arena-runtime.py" in text and "exec python3" in text and len(lines) <= 20
        support = path.name in SCRIPT_CLASS_ALLOW_SUPPORT
        has_runtime_logic = any(token in text for token in ["jq", "source \"$SCRIPT_DIR/utils.sh\"", "while [", "python3 - <<", "find "])
        source_compat_wrapper = path.name in {"utils.sh", "benchmark-utils.sh"} and ("support-utils" in text or "_arena_benchmark_utils" in text)
        if is_wrapper or source_compat_wrapper:
            classification = "wrapper"
            action = "keep"
        elif support:
            classification = "support_shell"
            action = "keep_until_consumers_removed"
        elif has_runtime_logic:
            classification = "legacy_runtime_logic"
            action = "port_or_replace"
        else:
            classification = "shell_entrypoint"
            action = "review"
        rows.append({"script": str(path.relative_to(_repo_root())), "lines": len(lines), "classification": classification, "recommended_action": action})
    counts: Dict[str, int] = {}
    for row in rows:
        counts[row["classification"]] = counts.get(row["classification"], 0) + 1
    result = {"generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), "counts": counts, "scripts": rows}
    _dump(result) if args.json else print("\n".join(f"{row['classification']}\t{row['script']}\t{row['recommended_action']}" for row in rows))
    return 0
