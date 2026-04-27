from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

VALID_SEVERITIES = {"critical", "high", "medium", "low"}


@dataclass(frozen=True)
class ReviewFinding:
    file: str
    line: int
    severity: str
    title: str
    confidence: int = 0
    description: str = ""
    suggestion: str = ""
    source_model: str = "unknown"
    role: str = "unknown"
    evidence: List[str] = field(default_factory=list)
    validation_status: str = "unverified"

    def __post_init__(self) -> None:
        if self.severity not in VALID_SEVERITIES:
            raise ValueError(f"invalid severity: {self.severity}")
        if self.line < 1:
            raise ValueError("line must be >= 1")
        if not 0 <= self.confidence <= 100:
            raise ValueError("confidence must be between 0 and 100")

    def to_dict(self) -> Dict[str, Any]:
        return {
            "file": self.file,
            "line": self.line,
            "severity": self.severity,
            "title": self.title,
            "confidence": self.confidence,
            "description": self.description,
            "suggestion": self.suggestion,
            "source_model": self.source_model,
            "role": self.role,
            "evidence": list(self.evidence),
            "validation_status": self.validation_status,
        }


@dataclass(frozen=True)
class ProviderResponse:
    provider: str
    model: str
    output_text: str
    raw: Optional[Dict[str, Any]] = None
    cost_usd: Optional[float] = None
    latency_ms: Optional[int] = None
    tool_calls: List[Dict[str, Any]] = field(default_factory=list)


@dataclass(frozen=True)
class ValidationIssue:
    path: str
    message: str

    def to_dict(self) -> Dict[str, str]:
        return {"path": self.path, "message": self.message}


def normalize_provider_payload(payload: Any) -> Tuple[Optional[Dict[str, Any]], List[ValidationIssue]]:
    issues: List[ValidationIssue] = []
    if not isinstance(payload, dict):
        return None, [ValidationIssue("$", "provider output must be a JSON object")]

    model = str(payload.get("model") or "unknown")
    role = str(payload.get("role") or "unknown")
    source_file = str(payload.get("file") or "")
    findings = payload.get("findings", [])
    if findings is None:
        findings = []
    if not isinstance(findings, list):
        return None, [ValidationIssue("$.findings", "findings must be an array")]

    normalized: List[Dict[str, Any]] = []
    for index, finding in enumerate(findings):
        path = f"$.findings[{index}]"
        if not isinstance(finding, dict):
            issues.append(ValidationIssue(path, "finding must be an object"))
            continue
        title = str(finding.get("title") or "").strip()
        if not title:
            issues.append(ValidationIssue(f"{path}.title", "title is required"))
            continue
        item = dict(finding)
        item["title"] = title
        item["file"] = str(item.get("file") or source_file)
        item["line"] = max(1, _coerce_int(item.get("line", payload.get("line", 1)), 1))
        item["confidence"] = min(100, max(0, _coerce_int(item.get("confidence", 50), 50)))
        item["severity"] = str(item.get("severity") or "medium").lower()
        if item["severity"] not in VALID_SEVERITIES:
            issues.append(ValidationIssue(f"{path}.severity", f"invalid severity normalized to medium: {item['severity']}"))
            item["severity"] = "medium"
        item.setdefault("description", "")
        item.setdefault("suggestion", "")
        if not isinstance(item.get("description"), str):
            issues.append(ValidationIssue(f"{path}.description", "description must be a string"))
            item["description"] = str(item.get("description") or "")
        if not isinstance(item.get("suggestion"), str):
            issues.append(ValidationIssue(f"{path}.suggestion", "suggestion must be a string"))
            item["suggestion"] = str(item.get("suggestion") or "")
        normalized.append(item)

    return {"model": model, "role": role, "file": source_file, "findings": normalized}, issues


def validate_provider_payload(payload: Any) -> List[ValidationIssue]:
    _, issues = normalize_provider_payload(payload)
    return issues


def _coerce_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default
