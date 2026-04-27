from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, Iterable, Sequence


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _plugin_dir() -> Path:
    override = os.environ.get("ARENA_UTILS_PLUGIN_DIR") or os.environ.get("ARENA_PLUGIN_DIR")
    return Path(override).resolve() if override else _repo_root()


def _load_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _dump(data: Any) -> None:
    print(json.dumps(data, ensure_ascii=False, indent=2))


def _deep_merge(base: Dict[str, Any], override: Dict[str, Any]) -> Dict[str, Any]:
    result = dict(base)
    for key, value in override.items():
        if isinstance(value, dict) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        else:
            result[key] = value
    return result


def _project_hash(path: str) -> str:
    return hashlib.sha256(path.encode("utf-8")).hexdigest()[:20]


def _json_path(data: Any, expr: str) -> Any:
    path = expr.strip()
    if path.endswith("// empty"):
        path = path[: -len("// empty")].strip()
    if path.startswith("."):
        path = path[1:]
    if not path:
        return data
    current = data
    for part in path.split("."):
        if not part:
            continue
        match = re.fullmatch(r"([^\[]+)(?:\[(\d+)\])?", part)
        if not match:
            return None
        key, index = match.group(1), match.group(2)
        if not isinstance(current, dict) or key not in current:
            return None
        current = current[key]
        if index is not None:
            if not isinstance(current, list):
                return None
            idx = int(index)
            if idx >= len(current):
                return None
            current = current[idx]
    return current


def _print_value(value: Any) -> None:
    if value is None:
        print("")
    elif isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, (dict, list)):
        print(json.dumps(value, ensure_ascii=False))
    else:
        print(value)


def _extract_json_text(text: str) -> str | None:
    stripped = text.strip()
    if not stripped:
        return None
    try:
        json.loads(stripped)
        return stripped
    except json.JSONDecodeError:
        pass
    fence = re.search(r"```(?:json)?\s*(.*?)\s*```", text, flags=re.DOTALL | re.IGNORECASE)
    if fence:
        candidate = fence.group(1).strip()
        try:
            json.loads(candidate)
            return candidate
        except json.JSONDecodeError:
            pass
    decoder = json.JSONDecoder()
    for index, char in enumerate(text):
        if char not in "[{":
            continue
        try:
            _data, end = decoder.raw_decode(text[index:])
        except json.JSONDecodeError:
            continue
        return text[index : index + end]
    return None


def _format_metric(value: float) -> str:
    if value == 0:
        return "0"
    text = f"{value:.3f}"
    if text.startswith("0."):
        return text[1:]
    return text


def _findings_from_json(text: str) -> list[dict[str, Any]]:
    try:
        data = json.loads(text)
    except json.JSONDecodeError:
        return []
    if isinstance(data, dict) and isinstance(data.get("findings"), list):
        data = data["findings"]
    return [item for item in data if isinstance(item, dict)] if isinstance(data, list) else []


def _extract_text(findings_json: str) -> str:
    parts: list[str] = []
    for item in _findings_from_json(findings_json):
        for key in ["title", "description", "suggestion"]:
            value = item.get(key)
            if value is not None:
                parts.append(str(value))
    return " ".join(parts)


def _truths(test_file: Path) -> list[dict[str, Any]]:
    try:
        data = _load_json(test_file)
    except Exception:
        return []
    value = data.get("ground_truth", []) if isinstance(data, dict) else []
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def _truth_matched(text: str, truth: dict[str, Any]) -> bool:
    lowered = text.lower()
    keywords = truth.get("description_contains", [])
    if isinstance(keywords, str):
        keywords = [keywords]
    return any(str(keyword).lower() in lowered for keyword in keywords if str(keyword))


def _severity_weight(value: str) -> int:
    return {"critical": 4, "high": 3, "medium": 2, "low": 1}.get(str(value or "").lower(), 1)


def _dependency_row(name: str, command: str, required: bool, hint: str) -> dict[str, Any]:
    path = shutil.which(command)
    version = ""
    if path:
        try:
            completed = subprocess.run([command, "--version"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=3, check=False)
            version = (completed.stdout or completed.stderr or "installed").splitlines()[0]
        except Exception:
            version = "installed"
    return {"name": name, "command": command, "required": required, "available": bool(path), "version": version, "install_hint": hint}


def cmd_support_utils(argv: Sequence[str]) -> int:
    if not argv:
        return 2
    command, *rest = list(argv)
    plugin = _plugin_dir()
    if command == "ensure-jq":
        if shutil.which("jq"):
            return 0
        print("[arena:error] jq is required but not found. Install: brew install jq", file=sys.stderr)
        return 1
    if command == "is-valid-json":
        text = rest[0] if rest else sys.stdin.read()
        try:
            json.loads(text)
            return 0
        except json.JSONDecodeError:
            return 1
    if command == "project-hash":
        print(_project_hash(rest[0]))
        return 0
    if command == "find-project-root":
        completed = subprocess.run(["git", "rev-parse", "--show-toplevel"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
        print(completed.stdout.strip() if completed.returncode == 0 and completed.stdout.strip() else os.getcwd())
        return 0
    if command == "cache-base-dir":
        print(plugin / "cache" / _project_hash(rest[0]))
        return 0
    if command == "merge-configs":
        configs: list[dict[str, Any]] = []
        for item in rest:
            path = Path(item)
            if path.exists():
                data = _load_json(path)
                if isinstance(data, dict):
                    configs.append(data)
        if not configs:
            print("{}")
            return 1
        merged: dict[str, Any] = {}
        for cfg in configs:
            merged = _deep_merge(merged, cfg)
        _dump(merged)
        return 0
    if command == "load-config":
        project_root = Path(rest[0]) if rest else None
        paths = [plugin / "config" / "default-config.json", Path.home() / ".claude" / ".ai-review-arena.json"]
        if project_root:
            paths.append(project_root / ".ai-review-arena.json")
        existing = [path for path in paths if path.exists()]
        if not existing:
            return 1
        if len(existing) == 1:
            print(existing[0])
            return 0
        merged: dict[str, Any] = {}
        for path in existing:
            data = _load_json(path)
            if isinstance(data, dict):
                merged = _deep_merge(merged, data)
        digest = hashlib.sha256(" ".join(str(path) for path in existing).encode("utf-8")).hexdigest()[:12]
        out = Path(tempfile.gettempdir()) / f"arena-config-merged.{digest}.json"
        out.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
        print(out)
        return 0
    if command == "load-config-file":
        project_root = Path(rest[0]) if rest else None
        candidates = []
        if project_root:
            candidates.append(project_root / ".ai-review-arena.json")
        candidates.extend([Path.home() / ".claude" / ".ai-review-arena.json", plugin / "config" / "default-config.json"])
        for path in candidates:
            if path.exists():
                print(path)
                return 0
        return 1
    if command == "get-config-value":
        if len(rest) < 2 or not Path(rest[0]).exists():
            return 1
        _print_value(_json_path(_load_json(Path(rest[0])), rest[1]))
        return 0
    if command == "extract-json":
        text = rest[0] if rest else sys.stdin.read()
        extracted = _extract_json_text(text)
        if extracted is None:
            return 1
        print(extracted)
        return 0
    if command == "get-current-year":
        print(datetime.now().year)
        return 0
    if command == "format-timestamp":
        print(datetime.fromtimestamp(float(rest[0])).strftime("%Y-%m-%d %H:%M:%S"))
        return 0
    if command == "validate-cache-content":
        text = rest[0] if rest else sys.stdin.read()
        patterns = [r"ignore (previous|prior|above|all) (instructions|prompts|rules)", r"you are now|new (system|base) prompt|override (system|your)", r"system prompt[:\s]|<\|im_start\|>system|<system>", r"(curl|wget|fetch|nc|ncat)\s+https?://[^ ]*\.(txt|log|env|key|pem|json)", "\u200b|\u200c|\u200d|\ufeff|\u2060"]
        return 1 if any(re.search(pattern, text, flags=re.IGNORECASE) for pattern in patterns) else 0
    if command in {"atomic-write", "atomic-write-stdin"}:
        target = Path(rest[0])
        target.parent.mkdir(parents=True, exist_ok=True)
        content = rest[1] if command == "atomic-write" and len(rest) > 1 else sys.stdin.read()
        fd, tmp_name = tempfile.mkstemp(prefix=target.name + ".", dir=str(target.parent))
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(content)
            if command == "atomic-write":
                handle.write("\n")
        os.replace(tmp_name, target)
        return 0
    if command == "pipeline-memory-snapshot":
        _dump({"working": [], "short_term": [], "long_term": [], "permanent": [], "snapshot_epoch": int(datetime.now().timestamp())})
        return 0
    if command == "pipeline-memory-reset":
        return 0
    if command == "timeout":
        if len(rest) < 2:
            return 2
        seconds = int(float(rest[0]))
        try:
            completed = subprocess.run(rest[1:], timeout=seconds, check=False)
            return completed.returncode
        except subprocess.TimeoutExpired:
            return 124
    if command == "safe-jq":
        if not rest:
            return 2
        completed = subprocess.run(["jq", "-r", *rest], text=True, input=None if len(rest) > 1 else sys.stdin.read(), check=False)
        return completed.returncode
    return 2


def cmd_benchmark_utils(argv: Sequence[str]) -> int:
    if not argv:
        return 2
    command, *rest = list(argv)
    if command == "extract-text":
        print(_extract_text(rest[0] if rest else sys.stdin.read()))
        return 0
    if command == "count-matches":
        if len(rest) < 3:
            return 2
        text, test_file, expected = rest[0], Path(rest[1]), int(rest[2])
        truths = _truths(test_file)[:expected]
        tp = sum(1 for truth in truths if _truth_matched(text, truth))
        print(f"{tp} {max(0, len(truths) - tp)}")
        return 0
    if command == "compute-metrics":
        tp, fp, fn = (int(rest[0]), int(rest[1]), int(rest[2]))
        precision = tp / (tp + fp) if tp + fp else 0.0
        recall = tp / (tp + fn) if tp + fn else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        print(f"{_format_metric(precision)} {_format_metric(recall)} {_format_metric(f1)}")
        return 0
    if command == "severity-weight":
        print(_severity_weight(rest[0] if rest else ""))
        return 0
    if command == "compute-weighted-f1":
        if len(rest) < 4:
            return 2
        text, findings_json, test_file, expected = rest[0], rest[1], Path(rest[2]), int(rest[3])
        truths = _truths(test_file)[:expected]
        weighted_tp = 0
        weighted_fn = 0
        tp_count = 0
        for truth in truths:
            weight = _severity_weight(str(truth.get("severity") or "medium"))
            if _truth_matched(text, truth):
                weighted_tp += weight
                tp_count += 1
            else:
                weighted_fn += weight
        actual = len(_findings_from_json(findings_json))
        weighted_fp = max(0, actual - tp_count) * 2
        precision = weighted_tp / (weighted_tp + weighted_fp) if weighted_tp + weighted_fp else 0.0
        recall = weighted_tp / (weighted_tp + weighted_fn) if weighted_tp + weighted_fn else 0.0
        f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
        print(_format_metric(f1))
        return 0
    return 2


def cmd_setup(argv: Sequence[str]) -> int:
    rows = [
        _dependency_row("jq", "jq", True, "brew install jq OR apt-get install jq"),
        _dependency_row("codex CLI", "codex", False, "npm install -g @openai/codex"),
        _dependency_row("gemini CLI", "gemini", False, "npm install -g @google/gemini-cli"),
        _dependency_row("gh CLI", "gh", False, "brew install gh OR https://cli.github.com"),
    ]
    prompt_dir = _plugin_dir() / "config" / "review-prompts"
    prompt_count = len(list(prompt_dir.glob("*.txt"))) if prompt_dir.exists() else 0
    required_missing = sum(1 for row in rows if row["required"] and not row["available"])
    print("ai-review-arena - Dependency Check")
    for row in rows:
        status = "OK" if row["available"] else ("MISSING" if row["required"] else "OPTIONAL")
        print(f"{row['name']}: {status} {row['version'] or row['install_hint']}")
    print(f"prompt templates: {'OK' if prompt_count else 'MISSING'} {prompt_count} templates")
    if not prompt_count:
        required_missing += 1
    print(f"Required missing: {required_missing}")
    return 1 if required_missing else 0


def cmd_setup_arena(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="setup-arena")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(list(argv))
    plugin = _plugin_dir()
    checks = [
        {"name": "jq", "status": "ok" if shutil.which("jq") else "missing"},
        {"name": "codex CLI", "status": "ok" if shutil.which("codex") else "optional"},
        {"name": "gemini CLI", "status": "ok" if shutil.which("gemini") else "optional"},
        {"name": "default-config.json", "status": "ok" if (plugin / "config" / "default-config.json").exists() else "missing"},
        {"name": "compliance-rules.json", "status": "ok" if (plugin / "config" / "compliance-rules.json").exists() else "optional"},
        {"name": "tech-queries.json", "status": "ok" if (plugin / "config" / "tech-queries.json").exists() else "optional"},
    ]
    cache_dir = plugin / "cache"
    cache_dir.mkdir(parents=True, exist_ok=True)
    checks.append({"name": "cache directory", "status": "ok" if os.access(cache_dir, os.W_OK) else "missing"})
    benchmarks = list((plugin / "config" / "benchmarks").glob("*.json")) if (plugin / "config" / "benchmarks").exists() else []
    prompts = list((plugin / "config" / "review-prompts").glob("*.txt")) if (plugin / "config" / "review-prompts").exists() else []
    checks.extend([
        {"name": "benchmark test cases", "status": "ok" if benchmarks else "optional", "count": len(benchmarks)},
        {"name": "review prompt templates", "status": "ok" if prompts else "missing", "count": len(prompts)},
    ])
    print("ai-review-arena - Extended Setup Check")
    for row in checks:
        detail = f" ({row['count']})" if "count" in row else ""
        print(f"{row['name']}: {row['status']}{detail}")
    if args.verbose:
        print(f"Plugin dir: {plugin}")
        print(f"Cache dir: {cache_dir}")
    missing = sum(1 for row in checks if row["status"] == "missing")
    print(f"Missing: {missing}")
    return 0
