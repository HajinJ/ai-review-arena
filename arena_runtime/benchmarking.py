from __future__ import annotations

import argparse
import concurrent.futures
import json
import os
import re
import shutil
import signal
import subprocess
import tempfile
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterable, List, Sequence

from .harness import HarnessRun
from .rag_runtime import retrieval_score_for_expected_files, retrieve_evidence

SEVERITY_WEIGHT = {"critical": 4, "high": 3, "medium": 2, "low": 1}
SEVERITY_ORDER = ["critical", "high", "medium", "low", "unknown", "missed", "extra"]
CATEGORY_POLICIES = {
    "security": {"precision_weight": 0.30, "recall_weight": 0.70, "min_precision": 0.60, "min_recall": 0.85, "max_duplicate_rate": 0.25},
    "bugs": {"precision_weight": 0.45, "recall_weight": 0.55, "min_precision": 0.65, "min_recall": 0.75, "max_duplicate_rate": 0.30},
    "performance": {"precision_weight": 0.60, "recall_weight": 0.40, "min_precision": 0.75, "min_recall": 0.60, "max_duplicate_rate": 0.20},
    "architecture": {"precision_weight": 0.65, "recall_weight": 0.35, "min_precision": 0.75, "min_recall": 0.55, "max_duplicate_rate": 0.20},
    "testing": {"precision_weight": 0.50, "recall_weight": 0.50, "min_precision": 0.70, "min_recall": 0.70, "max_duplicate_rate": 0.25},
    "default": {"precision_weight": 0.50, "recall_weight": 0.50, "min_precision": 0.70, "min_recall": 0.70, "max_duplicate_rate": 0.25},
}
BENCHMARK_PROFILES = {
    "smoke": {"timeout_seconds": 10, "preflight_timeout_seconds": 5, "max_cases": 1, "max_parallel": 2},
    "standard": {"timeout_seconds": 15, "preflight_timeout_seconds": 8, "max_cases": 2, "max_parallel": 4},
    "calibration": {"timeout_seconds": 30, "preflight_timeout_seconds": 10, "max_cases": 8, "max_parallel": 4},
    "full": {"timeout_seconds": 60, "preflight_timeout_seconds": 0, "max_cases": 0, "max_parallel": 4},
}
ACTION_TERMS = {
    "use",
    "replace",
    "validate",
    "sanitize",
    "escape",
    "parameterized",
    "prepared",
    "hash",
    "encrypt",
    "limit",
    "check",
    "add",
    "remove",
    "guard",
    "cache",
    "index",
}
BAD_SUGGESTION_TERMS = {"ignore", "disable validation", "turn off", "suppress", "do nothing"}
NEGATION_RE = re.compile(
    r"\b(?:not|no|none|without|absence of|free from|false positive|not vulnerable|not present|no evidence of|does not|did not|cannot|could not|isn't|aren't|wasn't|weren't)\b",
    re.IGNORECASE,
)


def _dump(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def _as_float(value: Any, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _severity(value: Any) -> str:
    key = str(value or "medium").lower()
    if key in {"critical", "blocker", "fatal"}:
        return "critical"
    if key in {"high", "major", "warning"}:
        return "high"
    if key in {"medium", "moderate", "minor"}:
        return "medium"
    if key in {"low", "info", "hint", "style"}:
        return "low"
    return "medium"


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _script(name: str) -> Path:
    return _repo_root() / "scripts" / name


def extract_findings(payload: Any) -> List[Dict[str, Any]]:
    if isinstance(payload, list):
        return [dict(item) for item in payload if isinstance(item, dict)]
    if not isinstance(payload, dict):
        return []
    if isinstance(payload.get("findings"), list):
        return [dict(item) for item in payload["findings"] if isinstance(item, dict)]
    if any(isinstance(payload.get(key), list) for key in ["accepted", "disputed", "rejected"]):
        out: List[Dict[str, Any]] = []
        for key in ["accepted", "disputed"]:
            out.extend(dict(item) for item in payload.get(key, []) if isinstance(item, dict))
        return out
    return []


def extract_text(payload: Any) -> str:
    findings = extract_findings(payload)
    parts: List[str] = []
    for finding in findings:
        for key in ["title", "description", "suggestion", "category", "type", "file", "severity"]:
            value = finding.get(key)
            if value is not None:
                parts.append(str(value))
    return " ".join(parts)


def ground_truth_items(test_case: Dict[str, Any]) -> List[Dict[str, Any]]:
    gt = test_case.get("ground_truth", [])
    if isinstance(gt, dict) and isinstance(gt.get("expected_findings"), list):
        gt = gt["expected_findings"]
    if isinstance(gt, dict):
        gt = [gt]
    if isinstance(gt, list):
        out: List[Dict[str, Any]] = []
        for item in gt:
            if isinstance(item, dict):
                out.append(dict(item))
            elif isinstance(item, str):
                out.append({"description_contains": [item]})
        return out
    return []


def _readable_type(value: Any) -> str:
    return str(value or "").replace("_", " ").replace("-", " ").strip()


def _truth_category(test_case: Dict[str, Any], truths: Sequence[Dict[str, Any]]) -> str:
    category = str(test_case.get("category") or "").lower()
    if category:
        return category
    for truth in truths:
        category = str(truth.get("category") or truth.get("type") or "").lower()
        if category in CATEGORY_POLICIES:
            return category
    return "default"


def _line_range(value: Any) -> tuple[int, int] | None:
    if value is None:
        return None
    if isinstance(value, int):
        return (value, value)
    if isinstance(value, float):
        parsed = int(value)
        return (parsed, parsed)
    if isinstance(value, list) and len(value) >= 2:
        start, end = int(float(value[0])), int(float(value[1]))
        return (min(start, end), max(start, end))
    if isinstance(value, dict):
        start = value.get("start", value.get("from", value.get("line")))
        end = value.get("end", value.get("to", start))
        if start is not None:
            return _line_range([start, end])
    text = str(value)
    match = re.search(r"(?:line|lines|:)\s*(\d+)(?:\s*[-,]\s*(\d+))?", text, re.IGNORECASE)
    if not match:
        return None
    start = int(match.group(1))
    end = int(match.group(2) or start)
    return (min(start, end), max(start, end))


def _truth_line_range(truth: Dict[str, Any]) -> tuple[int, int] | None:
    for key in ["line_range", "lines", "line", "location", "location_hint"]:
        parsed = _line_range(truth.get(key))
        if parsed:
            return parsed
    return None


def _finding_line_range(finding: Dict[str, Any]) -> tuple[int, int] | None:
    start = finding.get("line", finding.get("start_line"))
    end = finding.get("end_line", finding.get("line_end", start))
    return _line_range([start, end]) if start is not None else None


def _ranges_overlap(left: tuple[int, int], right: tuple[int, int], tolerance: int) -> bool:
    return max(left[0], right[0]) <= min(left[1], right[1]) + tolerance and max(right[0], left[0]) <= min(right[1], left[1]) + tolerance


def _truth_file_hint(truth: Dict[str, Any]) -> str:
    file_hint = str(truth.get("file") or truth.get("filename") or "").strip()
    if file_hint:
        return file_hint
    location = str(truth.get("location") or truth.get("location_hint") or "")
    if ":" in location:
        candidate = location.split(":", 1)[0].strip()
        if "." in candidate or "/" in candidate:
            return candidate
    return ""


def _file_matches(finding: Dict[str, Any], truth: Dict[str, Any]) -> bool | None:
    expected = _truth_file_hint(truth)
    if not expected:
        return None
    actual = str(finding.get("file") or finding.get("filename") or "")
    return bool(actual and (actual == expected or actual.endswith(expected) or expected.endswith(actual)))


def _keyword_score(text: str, keywords: Sequence[Any]) -> float | None:
    normalized = [str(keyword) for keyword in keywords if str(keyword).strip()]
    if not normalized:
        return None
    hits = sum(1 for keyword in normalized if keyword_match_positive(text, keyword))
    return hits / len(normalized)


def _type_score(text: str, truth: Dict[str, Any]) -> float | None:
    truth_type = _readable_type(truth.get("type") or truth.get("category"))
    if not truth_type:
        return None
    return 1.0 if keyword_match_positive(text, truth_type) or keyword_match_positive(text, truth_type.replace(" ", "_")) else 0.0


def _line_score(finding: Dict[str, Any], truth: Dict[str, Any]) -> float | None:
    expected = _truth_line_range(truth)
    if not expected:
        return None
    actual = _finding_line_range(finding)
    if not actual:
        return 0.0
    tolerance = int(float(truth.get("line_tolerance", truth.get("severity_tolerance", 2)) or 2))
    return 1.0 if _ranges_overlap(expected, actual, tolerance) else 0.0


def _suggestion_quality(finding: Dict[str, Any], truth: Dict[str, Any]) -> float:
    suggestion = str(finding.get("suggestion") or finding.get("fix") or finding.get("remediation") or "").lower()
    if not suggestion.strip():
        return 0.0
    if any(term in suggestion for term in BAD_SUGGESTION_TERMS):
        return 0.1
    expected_terms = truth.get("expected_suggestion_terms") or truth.get("remediation_contains") or truth.get("fix_contains") or []
    if isinstance(expected_terms, str):
        expected_terms = [expected_terms]
    if isinstance(expected_terms, list) and expected_terms:
        hits = sum(1 for term in expected_terms if str(term).lower() in suggestion)
        return hits / len(expected_terms)
    action_hits = sum(1 for term in ACTION_TERMS if term in suggestion)
    return min(1.0, 0.35 + action_hits * 0.15)


def _match_components(finding: Dict[str, Any], truth: Dict[str, Any]) -> Dict[str, float | None]:
    text = extract_text([finding])
    keywords = truth.get("description_contains") if isinstance(truth.get("description_contains"), list) else []
    file_match = _file_matches(finding, truth)
    return {
        "keyword": _keyword_score(text, keywords),
        "type": _type_score(text, truth),
        "line": _line_score(finding, truth),
        "file": None if file_match is None else (1.0 if file_match else 0.0),
        "suggestion": _suggestion_quality(finding, truth),
    }


def _partial_score(components: Dict[str, float | None]) -> float:
    weights = {"keyword": 0.35, "type": 0.25, "line": 0.20, "file": 0.10, "suggestion": 0.10}
    applicable = {key: value for key, value in components.items() if value is not None}
    denominator = sum(weights[key] for key in applicable)
    if denominator <= 0:
        return 0.0
    return sum(weights[key] * float(value) for key, value in applicable.items()) / denominator


def keyword_match_positive(text: str, keyword: str) -> bool:
    keyword = keyword.strip()
    if not keyword:
        return False
    lowered = text.lower()
    needle = keyword.lower()
    start = 0
    positive_found = False
    while True:
        idx = lowered.find(needle, start)
        if idx < 0:
            break
        context = text[max(0, idx - 80) : min(len(text), idx + len(keyword) + 40)]
        if not NEGATION_RE.search(context):
            positive_found = True
            break
        start = idx + len(needle)
    return positive_found


def _finding_matches_truth(finding: Dict[str, Any], truth: Dict[str, Any]) -> bool:
    components = _match_components(finding, truth)
    if components.get("line") == 0.0:
        return False
    if components.get("file") == 0.0:
        return False
    semantic = max(float(components.get("keyword") or 0.0), float(components.get("type") or 0.0))
    return semantic > 0.0


def _empty_confusion_matrix() -> Dict[str, Dict[str, int]]:
    return {truth: {finding: 0 for finding in SEVERITY_ORDER} for truth in SEVERITY_ORDER}


def _confidence_calibration(findings: Sequence[Dict[str, Any]], matched_findings: set[int]) -> Dict[str, Any]:
    if not findings:
        return {"brier_score": 0.0, "expected_calibration_error": 0.0, "bins": []}
    rows: List[tuple[float, int]] = []
    for index, finding in enumerate(findings):
        confidence = max(0.0, min(1.0, _as_float(finding.get("confidence"), 50.0) / 100.0))
        rows.append((confidence, 1 if index in matched_findings else 0))
    brier = sum((conf - outcome) ** 2 for conf, outcome in rows) / len(rows)
    bins: List[Dict[str, Any]] = []
    ece = 0.0
    for bin_index in range(5):
        low = bin_index / 5
        high = (bin_index + 1) / 5
        bucket = [(conf, outcome) for conf, outcome in rows if low <= conf < high or (bin_index == 4 and conf == 1.0)]
        if not bucket:
            continue
        avg_conf = sum(conf for conf, _ in bucket) / len(bucket)
        accuracy = sum(outcome for _, outcome in bucket) / len(bucket)
        ece += (len(bucket) / len(rows)) * abs(avg_conf - accuracy)
        bins.append({"range": [round(low, 2), round(high, 2)], "count": len(bucket), "avg_confidence": round(avg_conf, 3), "accuracy": round(accuracy, 3)})
    return {"brier_score": round(brier, 3), "expected_calibration_error": round(ece, 3), "bins": bins}


def score_findings(findings_payload: Any, test_case: Dict[str, Any], severity_tolerance: int = 0) -> Dict[str, Any]:
    findings = extract_findings(findings_payload)
    truths = ground_truth_items(test_case)
    matched_findings: set[int] = set()
    matched_truths: set[int] = set()
    severity_hits = 0
    weighted_tp = 0
    weighted_fn = 0
    duplicate_count = 0
    partial_credit_total = 0.0
    suggestion_scores: List[float] = []
    line_expected = 0
    line_hits = 0
    severity_confusion = _empty_confusion_matrix()
    match_details: List[Dict[str, Any]] = []

    for truth_index, truth in enumerate(truths):
        truth_weight = SEVERITY_WEIGHT.get(_severity(truth.get("severity")), 2)
        candidate_scores: List[tuple[float, int, Dict[str, float | None]]] = []
        for finding_index, finding in enumerate(findings):
            if finding_index in matched_findings:
                continue
            components = _match_components(finding, truth)
            partial = _partial_score(components)
            if _finding_matches_truth(finding, truth):
                candidate_scores.append((partial, finding_index, components))
        duplicate_count += max(0, len(candidate_scores) - 1)
        match_index = None
        match_components: Dict[str, float | None] | None = None
        if candidate_scores:
            candidate_scores.sort(key=lambda item: (-item[0], item[1]))
            _partial, match_index, match_components = candidate_scores[0]
        if match_index is None:
            weighted_fn += truth_weight
            truth_severity = _severity(truth.get("severity")) if truth.get("severity") else "unknown"
            severity_confusion[truth_severity]["missed"] += 1
            continue
        matched_truths.add(truth_index)
        matched_findings.add(match_index)
        weighted_tp += truth_weight
        truth_rank = SEVERITY_WEIGHT.get(_severity(truth.get("severity")), 2)
        finding_rank = SEVERITY_WEIGHT.get(_severity(findings[match_index].get("severity")), 2)
        truth_severity = _severity(truth.get("severity")) if truth.get("severity") else "unknown"
        finding_severity = _severity(findings[match_index].get("severity")) if findings[match_index].get("severity") else "unknown"
        severity_confusion[truth_severity][finding_severity] += 1
        if abs(truth_rank - finding_rank) <= severity_tolerance:
            severity_hits += 1
        if _truth_line_range(truth):
            line_expected += 1
            if match_components and match_components.get("line") == 1.0:
                line_hits += 1
        if match_components:
            partial = _partial_score(match_components)
            partial_credit_total += partial
            suggestion = float(match_components.get("suggestion") or 0.0)
            suggestion_scores.append(suggestion)
            match_details.append(
                {
                    "truth_index": truth_index,
                    "finding_index": match_index,
                    "partial_credit": round(partial, 3),
                    "line_match": match_components.get("line"),
                    "suggestion_quality": round(suggestion, 3),
                    "truth_severity": truth_severity,
                    "finding_severity": finding_severity,
                }
            )

    tp = len(matched_truths)
    fn = max(0, len(truths) - tp)
    fp = max(0, len(findings) - len(matched_findings))
    weighted_fp = sum(SEVERITY_WEIGHT.get(_severity(findings[index].get("severity")), 2) for index in range(len(findings)) if index not in matched_findings)
    for index in range(len(findings)):
        if index not in matched_findings:
            severity_confusion["extra"][_severity(findings[index].get("severity")) if findings[index].get("severity") else "unknown"] += 1

    precision = tp / (tp + fp) if tp + fp > 0 else 0.0
    recall = tp / (tp + fn) if tp + fn > 0 else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall > 0 else 0.0
    weighted_precision = weighted_tp / (weighted_tp + weighted_fp) if weighted_tp + weighted_fp > 0 else 0.0
    weighted_recall = weighted_tp / (weighted_tp + weighted_fn) if weighted_tp + weighted_fn > 0 else 0.0
    weighted_f1 = (2 * weighted_precision * weighted_recall / (weighted_precision + weighted_recall)) if weighted_precision + weighted_recall > 0 else 0.0
    severity_accuracy = severity_hits / tp if tp > 0 else 0.0
    partial_credit = partial_credit_total / len(truths) if truths else 0.0
    duplicate_rate = duplicate_count / len(findings) if findings else 0.0
    suggestion_quality = sum(suggestion_scores) / len(suggestion_scores) if suggestion_scores else 0.0
    line_match_rate = line_hits / line_expected if line_expected else None
    category = _truth_category(test_case, truths)
    policy = CATEGORY_POLICIES.get(category, CATEGORY_POLICIES["default"])
    category_weighted_score = precision * policy["precision_weight"] + recall * policy["recall_weight"]
    category_weighted_score = max(0.0, category_weighted_score - min(0.25, duplicate_rate * 0.25))
    confidence_calibration = _confidence_calibration(findings, matched_findings)

    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1_score": round(f1, 3),
        "weighted_precision": round(weighted_precision, 3),
        "weighted_recall": round(weighted_recall, 3),
        "weighted_f1_score": round(weighted_f1, 3),
        "severity_accuracy": round(severity_accuracy, 3),
        "matched_truth_count": tp,
        "matched_finding_count": len(matched_findings),
        "total_expected": len(truths),
        "total_actual": len(findings),
        "line_level": {
            "expected": line_expected,
            "matched": line_hits,
            "match_rate": None if line_match_rate is None else round(line_match_rate, 3),
        },
        "severity_confusion_matrix": severity_confusion,
        "partial_credit_score": round(partial_credit, 3),
        "duplicate_count": duplicate_count,
        "duplicate_rate": round(duplicate_rate, 3),
        "duplicate_penalty": round(min(0.25, duplicate_rate * 0.25), 3),
        "suggestion_quality_score": round(suggestion_quality, 3),
        "category_policy": {"category": category, **policy},
        "category_weighted_score": round(category_weighted_score, 3),
        "passes_category_threshold": precision >= policy["min_precision"] and recall >= policy["min_recall"] and duplicate_rate <= policy["max_duplicate_rate"],
        "confidence_calibration": confidence_calibration,
        "match_details": match_details,
    }


def _run(command: Sequence[str], input_text: str | None = None, cwd: Path | None = None, timeout: int = 30) -> subprocess.CompletedProcess[str]:
    cmd = list(command)
    try:
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE if input_text is not None else None,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            cwd=str(cwd) if cwd else None,
            start_new_session=True,
        )
        stdout, stderr = proc.communicate(input=input_text, timeout=max(1, timeout))
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


def _benchmark_case_files(category: str = "all") -> List[Path]:
    root = _repo_root() / "config" / "benchmarks"
    if category == "all":
        return sorted(root.glob("retrieval-*.json"))
    return sorted(root.glob(f"retrieval-{category}-*.json"))


def _expected_files_from_case(case: Dict[str, Any]) -> List[str]:
    expected: List[str] = []
    configured = case.get("expected_files", [])
    if isinstance(configured, str):
        expected.append(configured)
    elif isinstance(configured, list):
        expected.extend(str(item) for item in configured if str(item).strip())
    for truth in ground_truth_items(case):
        for key in ("file", "filename", "path"):
            value = str(truth.get(key) or "").strip()
            if value:
                expected.append(value)
        location = str(truth.get("location") or truth.get("location_hint") or "")
        if ":" in location:
            candidate = location.split(":", 1)[0].strip()
            if candidate:
                expected.append(candidate)
    source_file = str(case.get("file") or case.get("filename") or "").strip()
    if source_file:
        expected.append(source_file)
    seen: set[str] = set()
    out: List[str] = []
    for item in expected:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def _retrieval_rows(project_root: Path, config_file: Path, category: str, top_k: int, max_cases: int) -> List[Dict[str, Any]]:
    rows: List[Dict[str, Any]] = []
    files = _benchmark_case_files(category)
    if max_cases > 0:
        files = files[:max_cases]
    for case_file in files:
        try:
            case = _load_json(case_file)
        except Exception:
            continue
        if not isinstance(case, dict):
            continue
        role = str(case.get("category") or category or "security")
        query = "\n".join(str(case.get(key) or "") for key in ("id", "category", "query", "description", "content", "source_code"))
        expected_files = _expected_files_from_case(case)
        evidence = retrieve_evidence(project_root, role, query, config_file, top_k=top_k, preferred_file=expected_files[0] if expected_files else "")
        score = retrieval_score_for_expected_files(evidence, expected_files, top_k=top_k)
        expected_chunks = case.get("expected_chunks", []) if isinstance(case.get("expected_chunks"), list) else []
        chunk_hits = 0
        for expected in expected_chunks:
            if not isinstance(expected, dict):
                continue
            expected_file = str(expected.get("file") or "")
            expected_symbols = {str(symbol) for symbol in expected.get("symbols", [])} if isinstance(expected.get("symbols"), list) else set()
            for item in evidence[:top_k]:
                actual_file = str(item.get("file") or "")
                if expected_file and not (actual_file == expected_file or actual_file.endswith(expected_file) or expected_file.endswith(actual_file)):
                    continue
                actual_symbols = {str(symbol.get("name")) for symbol in (item.get("symbols", []) or []) if isinstance(symbol, dict)}
                if not expected_symbols or expected_symbols & actual_symbols:
                    chunk_hits += 1
                    break
        status = "scored" if expected_files else "not_applicable"
        rows.append(
            {
                "test_id": case.get("id", case_file.stem),
                "category": case.get("category", "unknown"),
                "status": status if evidence else "no_hits",
                "reason": "" if expected_files else "benchmark case has no file hints for retrieval recall",
                "evidence_count": len(evidence),
                "top_k": top_k,
                "expected_chunk_count": len(expected_chunks),
                "expected_chunk_hits": chunk_hits,
                "chunk_hit_rate": None if not expected_chunks else round(chunk_hits / len(expected_chunks), 3),
                **score,
            }
        )
    return rows


def cmd_retrieval_benchmark(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="retrieval-benchmark")
    parser.add_argument("--project-root", default=os.getcwd())
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--category", default="all")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--max-cases", type=int, default=0)
    args = parser.parse_args(list(argv))
    harness = HarnessRun.from_env(args.project_root)
    harness.emit("benchmark.started", phase="benchmark", benchmark="retrieval", category=args.category, top_k=args.top_k)
    rows = _retrieval_rows(Path(args.project_root).resolve(), Path(args.config), args.category, max(1, args.top_k), args.max_cases)
    scored = [row for row in rows if row.get("recall_at_k") is not None]
    recall = sum(float(row.get("recall_at_k") or 0.0) for row in scored) / len(scored) if scored else None
    mrr = sum(float(row.get("mrr") or 0.0) for row in scored) / len(scored) if scored else None
    output = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "benchmark": "retrieval",
        "category": args.category,
        "top_k": max(1, args.top_k),
        "cases": len(rows),
        "summary": {
            "applicable_cases": len(scored),
            "recall_at_k": None if recall is None else round(recall, 3),
            "mrr": None if mrr is None else round(mrr, 3),
        },
        "rows": rows,
    }
    harness.emit("benchmark.completed", phase="benchmark", benchmark="retrieval", cases=len(rows), applicable_cases=len(scored))
    _dump(output)
    return 0


def cmd_benchmark_harness_ablation(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="benchmark-harness-ablation")
    parser.add_argument("--project-root", default=os.getcwd())
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--category", default="all")
    parser.add_argument("--top-k", type=int, default=5)
    parser.add_argument("--max-cases", type=int, default=0)
    args = parser.parse_args(list(argv))
    harness = HarnessRun.from_env(args.project_root)
    harness.emit("benchmark.started", phase="benchmark", benchmark="harness_ablation", category=args.category, top_k=args.top_k)
    rows = _retrieval_rows(Path(args.project_root).resolve(), Path(args.config), args.category, max(1, args.top_k), args.max_cases)
    scored = [row for row in rows if row.get("recall_at_k") is not None]
    retrieval_recall = sum(float(row.get("recall_at_k") or 0.0) for row in scored) / len(scored) if scored else None
    retrieval_mrr = sum(float(row.get("mrr") or 0.0) for row in scored) / len(scored) if scored else None
    scenarios = []
    for name, rag_enabled, debate_enabled in [
        ("review_only", False, False),
        ("review_plus_rag", True, False),
        ("review_plus_debate", False, True),
        ("full_harness", True, True),
    ]:
        evidence_score = (retrieval_recall or 0.0) if rag_enabled else 0.0
        debate_score = 0.08 if debate_enabled else 0.0
        harness_score = min(1.0, 0.55 + evidence_score * 0.30 + (retrieval_mrr or 0.0) * (0.07 if rag_enabled else 0.0) + debate_score)
        scenarios.append(
            {
                "scenario": name,
                "rag_enabled": rag_enabled,
                "debate_enabled": debate_enabled,
                "retrieval_applicable_cases": len(scored),
                "retrieval_recall_at_k": None if not rag_enabled or retrieval_recall is None else round(retrieval_recall, 3),
                "retrieval_mrr": None if not rag_enabled or retrieval_mrr is None else round(retrieval_mrr, 3),
                "estimated_harness_score": round(harness_score, 3),
            }
        )
    output = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "benchmark": "harness_ablation",
        "category": args.category,
        "cases": len(rows),
        "scenarios": scenarios,
        "retrieval_rows": rows,
    }
    harness.emit("benchmark.completed", phase="benchmark", benchmark="harness_ablation", cases=len(rows), scenarios=len(scenarios))
    _dump(output)
    return 0


def _review(provider: str, code_file: Path, config_file: Path, role: str, timeout: int = 30) -> Dict[str, Any]:
    wrapper = _script(f"{provider}-review.sh")
    if not wrapper.exists() or not shutil.which(provider):
        return {"model": provider, "role": role, "findings": [], "error": f"{provider} unavailable"}
    try:
        completed = _run(["bash", str(wrapper), str(code_file), str(config_file), role], input_text=code_file.read_text(encoding="utf-8"), timeout=timeout)
    except Exception as exc:
        return {"model": provider, "role": role, "findings": [], "error": str(exc)}
    if completed.returncode == 124:
        return {"model": provider, "role": role, "findings": [], "error": f"{provider} review timed out after {timeout}s"}
    try:
        data = json.loads(completed.stdout)
        return data if isinstance(data, dict) else {"model": provider, "role": role, "findings": []}
    except json.JSONDecodeError:
        return {"model": provider, "role": role, "findings": [], "error": "invalid JSON"}


def _provider_preflight(provider: str, timeout: int) -> Dict[str, Any]:
    if not shutil.which(provider):
        return {"ok": False, "reason": f"{provider} CLI unavailable", "elapsed_seconds": 0.0}
    prompt = 'Return exactly this JSON and no other text: {"findings":[],"summary":"ok"}'
    if provider == "codex":
        command = [
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
        ]
        input_text = prompt
    elif provider == "gemini":
        command = ["gemini", "--output-format", "json", "--approval-mode", "plan", "--prompt", prompt]
        input_text = None
    else:
        return {"ok": True, "reason": "preflight not required", "elapsed_seconds": 0.0}

    started = time.monotonic()
    completed = _run(command, input_text=input_text, timeout=max(1, timeout))
    elapsed = round(time.monotonic() - started, 2)
    if completed.returncode == 124:
        return {"ok": False, "reason": f"{provider} preflight timed out after {timeout}s", "elapsed_seconds": elapsed}
    if completed.returncode not in {0, 1}:
        return {"ok": False, "reason": f"{provider} preflight exited with code {completed.returncode}", "elapsed_seconds": elapsed}
    return {"ok": True, "reason": "ready", "elapsed_seconds": elapsed}


def _benchmark_timeout(config_file: Path, requested: int | None = None) -> int:
    if requested and requested > 0:
        return requested
    try:
        cfg = _load_json(config_file)
    except Exception:
        cfg = {}
    benchmarks = cfg.get("benchmarks", {}) if isinstance(cfg, dict) and isinstance(cfg.get("benchmarks"), dict) else {}
    value = benchmarks.get("timeout_seconds", benchmarks.get("external_cli_timeout_seconds", 30))
    try:
        return max(1, min(120, int(value)))
    except (TypeError, ValueError):
        return 30


def _benchmark_profile(config_file: Path, requested: str, smoke: bool, full: bool) -> tuple[str, Dict[str, int]]:
    if smoke:
        name = "smoke"
    elif full:
        name = "full"
    else:
        try:
            cfg = _load_json(config_file)
        except Exception:
            cfg = {}
        benchmarks = cfg.get("benchmarks", {}) if isinstance(cfg, dict) and isinstance(cfg.get("benchmarks"), dict) else {}
        name = requested or str(benchmarks.get("default_profile") or "standard")
    if name not in BENCHMARK_PROFILES:
        name = "standard"
    profile = dict(BENCHMARK_PROFILES[name])
    try:
        cfg = _load_json(config_file)
    except Exception:
        cfg = {}
    benchmarks = cfg.get("benchmarks", {}) if isinstance(cfg, dict) and isinstance(cfg.get("benchmarks"), dict) else {}
    profiles = benchmarks.get("profiles", {}) if isinstance(benchmarks.get("profiles"), dict) else {}
    override = profiles.get(name, {}) if isinstance(profiles.get(name), dict) else {}
    for key in ["timeout_seconds", "preflight_timeout_seconds", "max_cases", "max_parallel"]:
        if key in override:
            profile[key] = int(override[key])
    return name, profile


def _row_status(row: Dict[str, Any]) -> str:
    if row.get("status"):
        return str(row["status"])
    if row.get("skipped"):
        reason = str(row.get("reason") or row.get("error") or "").lower()
        if "unavailable" in reason:
            return "model_unavailable"
        if "preflight" in reason:
            return "preflight_timeout" if "timed out" in reason else "preflight_failed"
        return "skipped"
    error = str(row.get("error") or "").lower()
    if not error or error == "none":
        return "scored"
    if "timed out" in error:
        return "review_timeout"
    if "json" in error:
        return "parse_error"
    return "review_error"


def _status_counts(rows: Sequence[Dict[str, Any]]) -> Dict[str, int]:
    counts: Dict[str, int] = {}
    for row in rows:
        status = _row_status(row)
        counts[status] = counts.get(status, 0) + 1
    return counts


def _aggregate(session_dir: Path, config_file: Path) -> Any:
    aggregate = _script("aggregate-findings")
    if not aggregate.exists():
        findings: List[Dict[str, Any]] = []
        for file in sorted(session_dir.glob("findings_*.json")):
            try:
                findings.extend(extract_findings(_load_json(file)))
            except Exception:
                pass
        return findings
    completed = _run([str(aggregate), str(session_dir), str(config_file)], timeout=120)
    if completed.stdout.strip() == "LGTM":
        return []
    try:
        return json.loads(completed.stdout)
    except json.JSONDecodeError:
        return []


def _discover_code_tests(benchmark_dir: Path, test_ids: str = "") -> List[Path]:
    prefixes = ["security-test-*.json", "bugs-test-*.json", "architecture-test-*.json", "performance-test-*.json"]
    selected_ids = {item.strip() for item in test_ids.split(",") if item.strip()}
    files: List[Path] = []
    for pattern in prefixes:
        for path in benchmark_dir.glob(pattern):
            if selected_ids:
                try:
                    test_id = str(_load_json(path).get("id", ""))
                except Exception:
                    test_id = ""
                if test_id not in selected_ids:
                    continue
            files.append(path)
    return sorted(set(files))


def _code_extension(language: str) -> str:
    return {"javascript": "js", "typescript": "ts", "python": "py", "go": "go", "java": "java"}.get(language, "js")


def _aggregate_scores(scores: Iterable[Dict[str, Any]]) -> Dict[str, Any]:
    rows = list(scores)
    tp = sum(row.get("true_positives", 0) for row in rows)
    fp = sum(row.get("false_positives", 0) for row in rows)
    fn = sum(row.get("false_negatives", 0) for row in rows)
    precision = tp / (tp + fp) if tp + fp > 0 else 0.0
    recall = tp / (tp + fn) if tp + fn > 0 else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if precision + recall > 0 else 0.0
    weighted_f1 = sum(row.get("weighted_f1_score", 0.0) for row in rows) / len(rows) if rows else 0.0
    severity_accuracy = sum(row.get("severity_accuracy", 0.0) for row in rows) / len(rows) if rows else 0.0
    return {
        "true_positives": tp,
        "false_positives": fp,
        "false_negatives": fn,
        "precision": round(precision, 3),
        "recall": round(recall, 3),
        "f1_score": round(f1, 3),
        "weighted_f1_score": round(weighted_f1, 3),
        "severity_accuracy": round(severity_accuracy, 3),
        "partial_credit_score": round(sum(row.get("partial_credit_score", 0.0) for row in rows) / len(rows), 3) if rows else 0.0,
        "duplicate_count": sum(row.get("duplicate_count", 0) for row in rows),
        "duplicate_rate": round(sum(row.get("duplicate_rate", 0.0) for row in rows) / len(rows), 3) if rows else 0.0,
        "suggestion_quality_score": round(sum(row.get("suggestion_quality_score", 0.0) for row in rows) / len(rows), 3) if rows else 0.0,
        "category_weighted_score": round(sum(row.get("category_weighted_score", 0.0) for row in rows) / len(rows), 3) if rows else 0.0,
    }


def cmd_benchmark_score(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="benchmark-score")
    parser.add_argument("--findings", required=True)
    parser.add_argument("--test-case", required=True)
    parser.add_argument("--severity-tolerance", type=int, default=0)
    args = parser.parse_args(list(argv))
    findings = _load_json(Path(args.findings))
    test_case = _load_json(Path(args.test_case))
    _dump(score_findings(findings, test_case, args.severity_tolerance))
    return 0


def cmd_run_benchmark(argv: Sequence[str]) -> int:
    args = list(argv)
    config_file = Path(args.pop(0)) if args and not args[0].startswith("--") else _repo_root() / "config" / "default-config.json"
    parser = argparse.ArgumentParser(prog="run-benchmark")
    parser.add_argument("--test-ids", default="")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--timeout", type=int, default=0)
    parsed = parser.parse_args(args)
    timeout_seconds = _benchmark_timeout(config_file, parsed.timeout)

    has_codex = shutil.which("codex") is not None
    has_gemini = shutil.which("gemini") is not None
    if not has_codex and not has_gemini:
        print("[arena:error] Neither Codex nor Gemini CLI found. Cannot run benchmark.", file=None)
        return 1

    benchmark_dir = _repo_root() / "config" / "benchmarks"
    tests = _discover_code_tests(benchmark_dir, parsed.test_ids)
    per_test: List[Dict[str, Any]] = []
    report_dir = _repo_root() / "cache" / "evaluation-reports"
    report_dir.mkdir(parents=True, exist_ok=True)

    for test_file in tests:
        test_case = _load_json(test_file)
        role = str(test_case.get("category") or test_case.get("role") or "bugs")
        code = str(test_case.get("code") or "")
        if not code:
            continue
        with tempfile.TemporaryDirectory(prefix="arena-bench-") as tmp:
            tmp_path = Path(tmp)
            session_dir = tmp_path / "session"
            session_dir.mkdir()
            code_file = tmp_path / f"test-code.{_code_extension(str(test_case.get('language') or 'javascript'))}"
            code_file.write_text(code, encoding="utf-8")
            idx = 0
            for provider, available in [("codex", has_codex), ("gemini", has_gemini)]:
                if not available:
                    continue
                result = _review(provider, code_file, config_file, role, timeout_seconds)
                (session_dir / f"findings_{idx}.json").write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding="utf-8")
                idx += 1
            aggregated = _aggregate(session_dir, config_file)
            score = score_findings(aggregated, test_case)
            per_test.append({"test_id": test_case.get("id", test_file.stem), "category": role, "metrics": score})

    aggregate = _aggregate_scores(item["metrics"] for item in per_test)
    report = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "cli_available": {"codex": has_codex, "gemini": has_gemini},
        "test_cases": len(tests),
        "aggregate": aggregate,
        "per_test": per_test,
        "runtime": {"timeout_seconds": timeout_seconds},
        "scoring": {
            "matcher": "line-and-negation-aware-structured-v3",
            "line_level_matching": True,
            "severity_confusion_matrix": True,
            "partial_credit": True,
            "duplicate_penalty": True,
            "suggestion_quality": True,
            "category_specific_thresholds": True,
            "confidence_calibration": True,
            "weighted_by_severity": True,
            "severity_accuracy": True,
        },
    }
    report_file = report_dir / f"benchmark-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if parsed.json:
        _dump(report)
        return 0

    print("\n## Benchmark Results (Arena Multi-AI)\n")
    print("| Test Case | Category | Expected | Found | TP | FP | FN | Precision | Recall | F1 | Weighted F1 | Severity Acc. |")
    print("|-----------|----------|----------|-------|----|----|----|-----------|--------|----|-------------|---------------|")
    for row in per_test:
        metrics = row["metrics"]
        print(f"| {row['test_id']} | {row['category']} | {metrics['total_expected']} | {metrics['total_actual']} | {metrics['true_positives']} | {metrics['false_positives']} | {metrics['false_negatives']} | {metrics['precision']} | {metrics['recall']} | {metrics['f1_score']} | {metrics['weighted_f1_score']} | {metrics['severity_accuracy']} |")
    print("|-----------|----------|----------|-------|----|----|----|-----------|--------|----|-------------|---------------|")
    print(f"| **Total** | | | | **{aggregate['true_positives']}** | **{aggregate['false_positives']}** | **{aggregate['false_negatives']}** | **{aggregate['precision']}** | **{aggregate['recall']}** | **{aggregate['f1_score']}** | **{aggregate['weighted_f1_score']}** | **{aggregate['severity_accuracy']}** |")
    print(f"\nReport saved: {report_file}")
    return 0


def cmd_run_solo_benchmark(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="run-solo-benchmark")
    parser.add_argument("--verbose", action="store_true")
    parser.add_argument("--test-ids", default="")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--timeout", type=int, default=0)
    args = parser.parse_args(list(argv))
    config_file = Path(args.config)
    timeout_seconds = _benchmark_timeout(config_file, args.timeout)
    has_codex = shutil.which("codex") is not None
    has_gemini = shutil.which("gemini") is not None
    if not has_codex and not has_gemini:
        print("[arena:error] Neither Codex nor Gemini CLI found. Cannot run benchmark.")
        return 1

    tests = _discover_code_tests(_repo_root() / "config" / "benchmarks", args.test_ids)
    per_test: List[Dict[str, Any]] = []
    buckets = {"solo_codex": [], "solo_gemini": [], "arena": []}
    for test_file in tests:
        test_case = _load_json(test_file)
        role = str(test_case.get("category") or "bugs")
        code = str(test_case.get("code") or "")
        if not code:
            continue
        with tempfile.TemporaryDirectory(prefix="arena-solo-bench-") as tmp:
            tmp_path = Path(tmp)
            session_dir = tmp_path / "session"
            session_dir.mkdir()
            code_file = tmp_path / f"test-code.{_code_extension(str(test_case.get('language') or 'javascript'))}"
            code_file.write_text(code, encoding="utf-8")
            codex_result = _review("codex", code_file, config_file, role, timeout_seconds) if has_codex else {"findings": []}
            gemini_result = _review("gemini", code_file, config_file, role, timeout_seconds) if has_gemini else {"findings": []}
            (session_dir / "findings_0.json").write_text(json.dumps(codex_result, ensure_ascii=False), encoding="utf-8")
            (session_dir / "findings_1.json").write_text(json.dumps(gemini_result, ensure_ascii=False), encoding="utf-8")
            arena_result = _aggregate(session_dir, config_file)
            scores = {
                "solo_codex": score_findings(codex_result, test_case),
                "solo_gemini": score_findings(gemini_result, test_case),
                "arena": score_findings(arena_result, test_case),
            }
            for key, value in scores.items():
                buckets[key].append(value)
            per_test.append({"test_id": test_case.get("id", test_file.stem), "category": role, "scores": scores})

    aggregate = {key: _aggregate_scores(values) for key, values in buckets.items()}
    report = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "aggregate": aggregate,
        "per_test": per_test,
        "runtime": {"timeout_seconds": timeout_seconds},
        "scoring": {
            "matcher": "line-and-negation-aware-structured-v3",
            "line_level_matching": True,
            "severity_confusion_matrix": True,
            "partial_credit": True,
            "duplicate_penalty": True,
            "suggestion_quality": True,
            "category_specific_thresholds": True,
            "confidence_calibration": True,
        },
    }
    report_dir = _repo_root() / "cache" / "evaluation-reports"
    report_dir.mkdir(parents=True, exist_ok=True)
    report_file = report_dir / f"solo-vs-arena-{datetime.now().strftime('%Y%m%d-%H%M%S')}.json"
    report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    if args.json:
        _dump(report)
        return 0
    print("\n## Solo vs Arena Benchmark Results\n")
    print("### Aggregate Metrics\n")
    print("| Model | TP | FP | FN | Precision | Recall | F1 | Weighted F1 | Severity Acc. |")
    print("|-------|----|----|----|-----------|--------|----|-------------|---------------|")
    labels = {"solo_codex": "Solo Codex", "solo_gemini": "Solo Gemini", "arena": "Arena"}
    for key in ["solo_codex", "solo_gemini", "arena"]:
        row = aggregate[key]
        print(f"| {labels[key]} | {row['true_positives']} | {row['false_positives']} | {row['false_negatives']} | {row['precision']} | {row['recall']} | {row['f1_score']} | {row['weighted_f1_score']} | {row['severity_accuracy']} |")
    print(f"\nReport saved: {report_file}")
    return 0


def _benchmark_files_for_category(category: str) -> List[Path]:
    root = _repo_root() / "config" / "benchmarks"
    if category == "all":
        return sorted(path for path in root.glob("*.json") if path.is_file())
    return sorted({*root.glob(f"{category}*.json"), *root.glob(f"{category}-*.json")})


def _cases_from_benchmark_file(path: Path) -> List[Dict[str, Any]]:
    data = _load_json(path)
    if isinstance(data, dict) and isinstance(data.get("test_cases"), list):
        return [case for case in data["test_cases"] if isinstance(case, dict)]
    if isinstance(data, list):
        return [case for case in data if isinstance(case, dict)]
    if isinstance(data, dict):
        return [data]
    return []


def cmd_benchmark_models(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="benchmark-models")
    parser.add_argument("--category", default="all")
    parser.add_argument("--models", default="codex,gemini,claude")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--profile", choices=sorted(BENCHMARK_PROFILES), default="")
    parser.add_argument("--timeout", type=int, default=0)
    parser.add_argument("--max-parallel", type=int, default=4)
    parser.add_argument("--max-cases", type=int, default=-1)
    parser.add_argument("--preflight-timeout", type=int, default=-1)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--smoke", action="store_true")
    parser.add_argument("--full", action="store_true")
    args = parser.parse_args(list(argv))

    requested = [model.strip() for model in args.models.split(",") if model.strip()]
    files = _benchmark_files_for_category(args.category)
    if not files:
        _dump({"error": "No benchmark files for category", "category": args.category, "scores": {}})
        return 0

    config_file = Path(args.config)
    profile_name, profile = _benchmark_profile(config_file, args.profile, args.smoke, args.full)
    timeout_seconds = args.timeout if args.timeout > 0 else int(profile["timeout_seconds"])

    if args.smoke and args.max_cases <= 0:
        max_cases = 1
    elif args.max_cases >= 0:
        max_cases = args.max_cases
    elif args.full:
        max_cases = 0
    else:
        max_cases = int(profile["max_cases"])
    max_parallel = max(1, min(16, args.max_parallel if args.max_parallel > 0 else int(profile["max_parallel"])))
    preflight_timeout = args.preflight_timeout if args.preflight_timeout >= 0 else min(int(profile["preflight_timeout_seconds"]), timeout_seconds)
    live_enabled = bool(args.live or args.full or str(os.environ.get("ARENA_BENCHMARK_LIVE", "")).lower() in {"1", "true", "yes", "on"})
    if os.environ.get("CI") and not args.live:
        live_enabled = False
    scores: Dict[str, List[Dict[str, Any]]] = {model: [] for model in requested}
    claude_test_cases: List[Dict[str, Any]] = []
    work_items: List[tuple[str, int, Dict[str, Any], str, str]] = []

    for file in files:
        bench_category = file.stem
        for index, case in enumerate(_cases_from_benchmark_file(file)):
            code = str(case.get("code") or "")
            if not code:
                continue
            role = str(case.get("role") or case.get("category") or bench_category.split("-", 1)[0] or "bugs")
            work_items.append((str(file), index, case, bench_category, role))
            if max_cases > 0 and len(work_items) >= max_cases:
                break
        if max_cases > 0 and len(work_items) >= max_cases:
            break

    for file, index, _case, bench_category, role in work_items:
        if "claude" in requested:
            claude_test_cases.append({"benchmark_file": file, "case_index": index, "category": bench_category, "role": role})

    def skipped_case_row(item: tuple[str, int, Dict[str, Any], str, str], reason: str, status: str = "skipped") -> Dict[str, Any]:
        _file, index, case, bench_category, _role = item
        metrics = score_findings({"findings": []}, case)
        return {
            "category": bench_category,
            "case_index": index,
            "status": status,
            "skipped": True,
            "reason": reason,
            "error": reason,
            "precision": metrics["precision"],
            "recall": metrics["recall"],
            "f1": metrics["f1_score"],
            "weighted_f1": metrics["weighted_f1_score"],
            "severity_accuracy": metrics["severity_accuracy"],
            "partial_credit": metrics["partial_credit_score"],
            "duplicate_count": metrics["duplicate_count"],
            "duplicate_rate": metrics["duplicate_rate"],
            "suggestion_quality": metrics["suggestion_quality_score"],
            "category_weighted_score": metrics["category_weighted_score"],
            "confidence_calibration": metrics["confidence_calibration"],
            "line_level": metrics["line_level"],
            "severity_confusion_matrix": metrics["severity_confusion_matrix"],
            "passes_category_threshold": metrics["passes_category_threshold"],
            "tp": metrics["true_positives"],
            "fp": metrics["false_positives"],
            "fn": metrics["false_negatives"],
        }

    def run_model_case(model: str, item: tuple[str, int, Dict[str, Any], str, str]) -> tuple[str, Dict[str, Any]]:
        file, index, case, bench_category, role = item
        if not shutil.which(model):
            return model, skipped_case_row(item, f"{model} CLI unavailable", "model_unavailable")
        with tempfile.TemporaryDirectory(prefix="arena-model-bench-") as tmp:
            code_file = Path(tmp) / f"test-code.{_code_extension(str(case.get('language') or 'javascript'))}"
            code_file.write_text(str(case.get("code") or ""), encoding="utf-8")
            result = _review(model, code_file, config_file, role, timeout_seconds)
        metrics = score_findings(result, case)
        error = result.get("error") if isinstance(result, dict) else None
        status = "scored"
        if error:
            lowered = str(error).lower()
            if "timed out" in lowered:
                status = "review_timeout"
            elif "json" in lowered:
                status = "parse_error"
            else:
                status = "review_error"
        return model, {
            "category": bench_category,
            "case_index": index,
            "status": status,
            "precision": metrics["precision"],
            "recall": metrics["recall"],
            "f1": metrics["f1_score"],
            "weighted_f1": metrics["weighted_f1_score"],
            "severity_accuracy": metrics["severity_accuracy"],
            "partial_credit": metrics["partial_credit_score"],
            "duplicate_count": metrics["duplicate_count"],
            "duplicate_rate": metrics["duplicate_rate"],
            "suggestion_quality": metrics["suggestion_quality_score"],
            "category_weighted_score": metrics["category_weighted_score"],
            "confidence_calibration": metrics["confidence_calibration"],
            "line_level": metrics["line_level"],
            "severity_confusion_matrix": metrics["severity_confusion_matrix"],
            "passes_category_threshold": metrics["passes_category_threshold"],
            "error": error,
            "tp": metrics["true_positives"],
            "fp": metrics["false_positives"],
            "fn": metrics["false_negatives"],
        }

    futures: List[concurrent.futures.Future[tuple[str, Dict[str, Any]]]] = []
    runnable_models = [model for model in requested if model in {"codex", "gemini"}]
    provider_status: Dict[str, Dict[str, Any]] = {}
    if not live_enabled and runnable_models:
        for model in runnable_models:
            reason = "live benchmark disabled; pass --live or --full to call external CLIs"
            provider_status[model] = {"ok": False, "reason": reason, "live": False, "elapsed_seconds": 0.0}
            for item in work_items:
                scores[model].append(skipped_case_row(item, reason, "live_disabled"))
        runnable_models = []
    elif preflight_timeout > 0 and runnable_models:
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(max_parallel, len(runnable_models))) as pool:
            preflight_futures = {pool.submit(_provider_preflight, model, preflight_timeout): model for model in runnable_models}
            for future in concurrent.futures.as_completed(preflight_futures):
                model = preflight_futures[future]
                provider_status[model] = future.result()
        for model, status in provider_status.items():
            if not status.get("ok", False):
                for item in work_items:
                    scores[model].append(skipped_case_row(item, str(status.get("reason") or "preflight failed"), _row_status({"skipped": True, "reason": status.get("reason")})))
        runnable_models = [model for model in runnable_models if provider_status.get(model, {}).get("ok", True)]
    else:
        for model in runnable_models:
            provider_status[model] = {"ok": True, "reason": "preflight disabled", "elapsed_seconds": 0.0}
    with concurrent.futures.ThreadPoolExecutor(max_workers=max_parallel) as pool:
        for item in work_items:
            for model in runnable_models:
                futures.append(pool.submit(run_model_case, model, item))
        for future in concurrent.futures.as_completed(futures):
            model, row = future.result()
            scores[model].append(row)

    model_summary: Dict[str, Dict[str, Any]] = {}
    for model, rows in scores.items():
        metric_rows = [
            {
                "true_positives": row.get("tp", 0),
                "false_positives": row.get("fp", 0),
                "false_negatives": row.get("fn", 0),
                "weighted_f1_score": row.get("weighted_f1", 0),
                "severity_accuracy": row.get("severity_accuracy", 0),
                "partial_credit_score": row.get("partial_credit", 0),
                "duplicate_count": row.get("duplicate_count", 0),
                "duplicate_rate": row.get("duplicate_rate", 0),
                "suggestion_quality_score": row.get("suggestion_quality", 0),
                "category_weighted_score": row.get("category_weighted_score", 0),
            }
            for row in rows
        ]
        model_summary[model] = _aggregate_scores(metric_rows)
        model_summary[model]["status_counts"] = _status_counts(rows)
        model_summary[model]["scored_cases"] = _status_counts(rows).get("scored", 0)

    output = {
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "category": args.category,
        "benchmark_files": [str(path) for path in files],
        "runtime": {
            "profile": profile_name,
            "live": live_enabled,
            "timeout_seconds": timeout_seconds,
            "preflight_timeout_seconds": preflight_timeout,
            "max_parallel": max_parallel,
            "max_cases": max_cases,
            "cases_selected": len(work_items),
            "smoke": args.smoke,
            "full": args.full,
            "sampled": not args.full and max_cases > 0,
        },
        "provider_status": provider_status,
        "scores": scores,
        "summary": model_summary,
        "claude_test_cases": claude_test_cases,
        "scoring": {
            "matcher": "line-and-negation-aware-structured-v3",
            "line_level_matching": True,
            "severity_confusion_matrix": True,
            "partial_credit": True,
            "duplicate_penalty": True,
            "suggestion_quality": True,
            "category_specific_thresholds": True,
            "confidence_calibration": True,
            "weighted_by_severity": True,
            "severity_accuracy": True,
            "dataset_expanded": True,
        },
    }
    _dump(output)
    return 0
