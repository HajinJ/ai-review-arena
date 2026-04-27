from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable, List, Sequence, Set, Tuple

SEVERITY_WEIGHT = {"low": 1.0, "medium": 1.5, "high": 2.0, "critical": 3.0}


@dataclass(frozen=True)
class Finding:
    file: str
    line: int
    severity: str
    title: str
    confidence: int = 0


@dataclass(frozen=True)
class GroundTruth:
    file: str
    line: int
    severity: str
    title: str


@dataclass(frozen=True)
class Score:
    true_positives: int
    false_positives: int
    false_negatives: int
    precision: float
    recall: float
    f1: float
    weighted_f1: float


class SeverityCalibrator:
    def calibrate(self, severity: str, confidence: int) -> float:
        return SEVERITY_WEIGHT.get(severity, 1.0) * max(0, min(100, confidence)) / 100.0


def score_findings(findings: Sequence[Finding], truth: Sequence[GroundTruth], *, line_tolerance: int = 0) -> Score:
    matched_truth: Set[int] = set()
    tp = 0
    fp = 0
    weighted_tp = 0.0
    weighted_total = sum(SEVERITY_WEIGHT.get(item.severity, 1.0) for item in truth) or 1.0

    for finding in findings:
        match = _find_match(finding, truth, matched_truth, line_tolerance)
        if match is None:
            fp += 1
            continue
        matched_truth.add(match)
        tp += 1
        weighted_tp += SEVERITY_WEIGHT.get(truth[match].severity, 1.0)

    fn = len(truth) - len(matched_truth)
    precision = tp / (tp + fp) if (tp + fp) else 1.0
    recall = tp / (tp + fn) if (tp + fn) else 1.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) else 0.0
    weighted_recall = weighted_tp / weighted_total
    weighted_f1 = (2 * precision * weighted_recall / (precision + weighted_recall)) if (precision + weighted_recall) else 0.0
    return Score(tp, fp, fn, precision, recall, f1, weighted_f1)


def _find_match(finding: Finding, truth: Sequence[GroundTruth], used: Set[int], line_tolerance: int) -> int | None:
    finding_terms = _terms(finding.title)
    best: Tuple[int, int] | None = None
    for idx, expected in enumerate(truth):
        if idx in used or finding.file != expected.file:
            continue
        if abs(finding.line - expected.line) > line_tolerance:
            continue
        overlap = len(finding_terms & _terms(expected.title))
        if overlap == 0:
            continue
        if best is None or overlap > best[1]:
            best = (idx, overlap)
    return None if best is None else best[0]


def _terms(value: str) -> Set[str]:
    return {part.lower() for part in value.replace("_", " ").replace("-", " ").split() if part}
