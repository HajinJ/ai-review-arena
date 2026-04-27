from __future__ import annotations

import argparse
import hashlib
import json
import os
import time
import uuid
import urllib.request
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

SECRET_NAME_FRAGMENTS = ("API_KEY", "TOKEN", "SECRET", "PASSWORD", "CREDENTIAL", "PRIVATE_KEY")


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _utc_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _new_run_id() -> str:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d-%H%M%S")
    return f"run-{stamp}-{uuid.uuid4().hex[:8]}"


def _trace_id(run_id: str) -> str:
    return hashlib.sha256(run_id.encode("utf-8")).hexdigest()[:32]


def _span_id(*parts: Any) -> str:
    raw = "|".join(str(part) for part in parts)
    return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def _is_secret_key(key: str) -> bool:
    upper = key.upper()
    return any(fragment in upper for fragment in SECRET_NAME_FRAGMENTS)


def _sanitize(value: Any, *, key: str = "", max_string: int = 12000) -> Any:
    if _is_secret_key(key):
        return "[redacted]"
    if isinstance(value, Mapping):
        return {str(k): _sanitize(v, key=str(k), max_string=max_string) for k, v in value.items()}
    if isinstance(value, list):
        return [_sanitize(item, max_string=max_string) for item in value[:200]]
    if isinstance(value, tuple):
        return [_sanitize(item, max_string=max_string) for item in value[:200]]
    if isinstance(value, (str, int, float, bool)) or value is None:
        if isinstance(value, str) and len(value) > max_string:
            return value[:max_string] + "...[truncated]"
        return value
    return str(value)


def _flatten(prefix: str, value: Any) -> Iterable[tuple[str, Any]]:
    if isinstance(value, Mapping):
        for key, item in value.items():
            next_prefix = f"{prefix}.{key}" if prefix else str(key)
            yield from _flatten(next_prefix, item)
        return
    if isinstance(value, list):
        yield prefix, json.dumps(value, ensure_ascii=False, separators=(",", ":"))
        return
    yield prefix, value


@dataclass(frozen=True)
class HarnessEvent:
    id: str
    run_id: str
    trace_id: str
    span_id: str
    parent_span_id: str
    event: str
    phase: str
    ts: float
    timestamp: str
    fields: dict[str, Any]

    def to_dict(self) -> dict[str, Any]:
        return {
            "schema_version": "1.0",
            "id": self.id,
            "run_id": self.run_id,
            "trace_id": self.trace_id,
            "span_id": self.span_id,
            "parent_span_id": self.parent_span_id,
            "event": self.event,
            "phase": self.phase,
            "ts": self.ts,
            "timestamp": self.timestamp,
            "fields": self.fields,
        }


class HarnessRun:
    def __init__(
        self,
        project_root: str | os.PathLike[str] | None = None,
        *,
        run_id: str | None = None,
        run_dir: str | os.PathLike[str] | None = None,
        metadata: Mapping[str, Any] | None = None,
    ) -> None:
        self.project_root = Path(project_root or os.getcwd()).resolve()
        self.run_id = run_id or os.environ.get("ARENA_RUN_ID") or _new_run_id()
        self.trace_id = _trace_id(self.run_id)
        self.run_dir = Path(run_dir).resolve() if run_dir else _repo_root() / "cache" / "runs" / self.run_id
        self.run_dir.mkdir(parents=True, exist_ok=True)
        self.events_path = self.run_dir / "events.jsonl"
        self.state_path = self.run_dir / "state.json"
        self.otel_path = self.run_dir / "otel-spans.jsonl"
        if metadata:
            self.checkpoint("initialized", **dict(metadata))

    @classmethod
    def from_env(cls, project_root: str | os.PathLike[str] | None = None) -> "HarnessRun":
        return cls(
            project_root=project_root,
            run_id=os.environ.get("ARENA_RUN_ID") or None,
            run_dir=os.environ.get("ARENA_RUN_DIR") or None,
        )

    def emit(self, event: str, *, phase: str = "", parent_span_id: str = "", **fields: Any) -> HarnessEvent:
        event_id = str(uuid.uuid4())
        ts = time.time()
        row = HarnessEvent(
            id=event_id,
            run_id=self.run_id,
            trace_id=self.trace_id,
            span_id=_span_id(self.run_id, event_id, event, ts),
            parent_span_id=parent_span_id,
            event=event,
            phase=phase,
            ts=ts,
            timestamp=_utc_now(),
            fields=_sanitize(fields),
        )
        with self.events_path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row.to_dict(), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
        return row

    def checkpoint(self, status: str, **fields: Any) -> None:
        payload = {
            "schema_version": "1.0",
            "run_id": self.run_id,
            "trace_id": self.trace_id,
            "project_root": str(self.project_root),
            "run_dir": str(self.run_dir),
            "status": status,
            "updated_at": _utc_now(),
            "fields": _sanitize(fields),
        }
        self.state_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")

    def export_otel_jsonl(self, output_path: str | os.PathLike[str] | None = None) -> Path:
        destination = Path(output_path).resolve() if output_path else self.otel_path
        with self.events_path.open("r", encoding="utf-8") as source, destination.open("w", encoding="utf-8") as out:
            for line in source:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                out.write(json.dumps(to_otel_span(event), ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n")
        return destination

    def export_otlp_json(self, output_path: str | os.PathLike[str] | None = None) -> Path:
        destination = Path(output_path).resolve() if output_path else self.run_dir / "otlp-traces.json"
        spans: list[dict[str, Any]] = []
        with self.events_path.open("r", encoding="utf-8") as source:
            for line in source:
                try:
                    event = json.loads(line)
                except json.JSONDecodeError:
                    continue
                spans.append(to_otel_span(event))
        payload = {
            "resourceSpans": [
                {
                    "resource": {
                        "attributes": [
                            {"key": "service.name", "value": {"stringValue": "ai-review-arena"}},
                            {"key": "arena.run_id", "value": {"stringValue": self.run_id}},
                        ]
                    },
                    "scopeSpans": [{"scope": {"name": "arena_runtime.harness"}, "spans": spans}],
                }
            ]
        }
        destination.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        return destination

    def push_otlp_http_json(self, endpoint: str, *, timeout: int = 10) -> dict[str, Any]:
        tmp = self.export_otlp_json()
        body = tmp.read_bytes()
        request = urllib.request.Request(endpoint, data=body, headers={"Content-Type": "application/json"}, method="POST")
        with urllib.request.urlopen(request, timeout=max(1, timeout)) as response:
            response_body = response.read(4096).decode("utf-8", errors="replace")
            return {"status": "pushed", "endpoint": endpoint, "status_code": response.status, "response": response_body}


def to_otel_span(event: Mapping[str, Any]) -> dict[str, Any]:
    ts = float(event.get("ts") or time.time())
    fields = event.get("fields", {}) if isinstance(event.get("fields"), Mapping) else {}
    duration_ms = int(fields.get("duration_ms") or fields.get("latency_ms") or 1)
    start_ns = int(ts * 1_000_000_000)
    end_ns = start_ns + max(1, duration_ms) * 1_000_000
    attrs: list[dict[str, Any]] = [
        {"key": "arena.run_id", "value": {"stringValue": str(event.get("run_id", ""))}},
        {"key": "arena.phase", "value": {"stringValue": str(event.get("phase", ""))}},
        {"key": "arena.event_id", "value": {"stringValue": str(event.get("id", ""))}},
    ]
    for key, value in _flatten("", fields):
        if value is None:
            continue
        attr_value: dict[str, Any]
        if isinstance(value, bool):
            attr_value = {"boolValue": value}
        elif isinstance(value, int):
            attr_value = {"intValue": value}
        elif isinstance(value, float):
            attr_value = {"doubleValue": value}
        else:
            attr_value = {"stringValue": str(value)}
        attrs.append({"key": f"arena.{key}", "value": attr_value})
    return {
        "traceId": str(event.get("trace_id") or _trace_id(str(event.get("run_id", "")))),
        "spanId": str(event.get("span_id") or _span_id(event.get("id", ""))),
        "parentSpanId": str(event.get("parent_span_id") or ""),
        "name": str(event.get("event") or "arena.event"),
        "kind": "SPAN_KIND_INTERNAL",
        "startTimeUnixNano": str(start_ns),
        "endTimeUnixNano": str(end_ns),
        "attributes": attrs,
        "status": {"code": "STATUS_CODE_OK"},
    }


def cmd_harness_event(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="harness-event")
    parser.add_argument("event")
    parser.add_argument("--phase", default="")
    parser.add_argument("--project-root", default=os.getcwd())
    parser.add_argument("--run-id", default="")
    parser.add_argument("--run-dir", default="")
    parser.add_argument("--field", action="append", default=[])
    args = parser.parse_args(list(argv))
    fields: dict[str, Any] = {}
    for item in args.field:
        if "=" not in item:
            fields[item] = True
            continue
        key, value = item.split("=", 1)
        fields[key] = value
    run = HarnessRun(args.project_root, run_id=args.run_id or None, run_dir=args.run_dir or None)
    event = run.emit(args.event, phase=args.phase, **fields)
    print(json.dumps(event.to_dict(), ensure_ascii=False, indent=2))
    return 0


def cmd_otel_export(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="otel-export")
    parser.add_argument("--events", default="")
    parser.add_argument("--run-dir", default="")
    parser.add_argument("--output", default="")
    parser.add_argument("--format", choices=["jsonl", "otlp-json"], default="jsonl")
    parser.add_argument("--project-root", default=os.getcwd())
    args = parser.parse_args(list(argv))
    if args.events:
        events_path = Path(args.events)
        run_id = events_path.parent.name
        run = HarnessRun(args.project_root, run_id=run_id, run_dir=events_path.parent)
        run.events_path = events_path
    else:
        run_dir_value = args.run_dir or os.environ.get("ARENA_RUN_DIR", "")
        if not run_dir_value:
            print(json.dumps({"error": "Provide --events or --run-dir"}, ensure_ascii=False))
            return 1
        run_dir = Path(run_dir_value)
        run = HarnessRun(args.project_root, run_id=run_dir.name, run_dir=run_dir)
    output = run.export_otlp_json(args.output or None) if args.format == "otlp-json" else run.export_otel_jsonl(args.output or None)
    print(json.dumps({"status": "exported", "output": str(output)}, ensure_ascii=False, indent=2))
    return 0


def cmd_otel_push(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="otel-push")
    parser.add_argument("--run-dir", required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--timeout", type=int, default=10)
    args = parser.parse_args(list(argv))
    run_dir = Path(args.run_dir)
    run = HarnessRun(run_dir=run_dir, run_id=run_dir.name)
    result = run.push_otlp_http_json(args.endpoint, timeout=args.timeout)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0
