from __future__ import annotations

import fnmatch
import json
import time
import uuid
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

SECRET_PATTERNS = ("*API_KEY*", "*TOKEN*", "*SECRET*", "*PASSWORD*", "*_KEY")


def should_redact_name(name: str, patterns: Iterable[str] = SECRET_PATTERNS) -> bool:
    upper = name.upper()
    return any(fnmatch.fnmatch(upper, pattern.upper()) for pattern in patterns)


def redact_text(value: str, secrets: Iterable[str] = ()) -> str:
    redacted = value
    for secret in secrets:
        if secret and len(secret) >= 4:
            redacted = redacted.replace(secret, "[redacted]")
    return redacted


def redact_mapping(mapping: Mapping[str, str], patterns: Iterable[str] = SECRET_PATTERNS) -> dict[str, str]:
    return {key: "[redacted]" if should_redact_name(key, patterns) else value for key, value in mapping.items()}


class TraceLogger:
    def __init__(self, path: Path) -> None:
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)

    def record(self, event: str, **fields: Any) -> None:
        row = {"id": str(uuid.uuid4()), "ts": time.time(), "event": event, **fields}
        with self.path.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")

    def record_cli_call(
        self,
        *,
        provider: str,
        command: Sequence[str],
        model: str,
        exit_code: int | None,
        latency_ms: int,
        stdout_bytes: int,
        stderr_bytes: int,
        timed_out: bool,
        structured_output: bool,
        schema_requested: bool,
    ) -> None:
        self.record(
            "cli_call",
            provider=provider,
            command=[redact_text(str(part)) for part in command],
            model=model,
            exit_code=exit_code,
            latency_ms=latency_ms,
            stdout_bytes=stdout_bytes,
            stderr_bytes=stderr_bytes,
            timed_out=timed_out,
            structured_output=structured_output,
            schema_requested=schema_requested,
        )
