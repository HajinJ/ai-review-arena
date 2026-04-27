from __future__ import annotations

import argparse
import json
import os
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, Iterable, List

from .config import load_json_config
from .observability import TraceLogger

DEFAULT_EXTENSIONS = {".ts", ".tsx", ".js", ".jsx", ".py", ".go", ".rs", ".java", ".kt", ".swift", ".rb", ".php", ".c", ".cpp", ".cs"}


@dataclass(frozen=True)
class HookResult:
    accepted: bool
    reason: str
    batch_ready: bool = False

    def to_dict(self) -> Dict[str, Any]:
        return {"accepted": self.accepted, "reason": self.reason, "batch_ready": self.batch_ready}


class HookOrchestrator:
    def __init__(self, project_root: Path, config: Dict[str, Any], session_dir: Path) -> None:
        self.project_root = project_root
        self.config = config
        self.session_dir = session_dir
        self.session_dir.mkdir(parents=True, exist_ok=True)
        self.trace = TraceLogger(self.session_dir / "trace.jsonl")

    def handle_post_tool_use(self, payload: Dict[str, Any]) -> HookResult:
        payload = self._normalize_hook_payload(payload)
        if not self.config.get("hook_mode", {}).get("enabled", True):
            return HookResult(False, "hook disabled")
        tool_name = payload.get("tool_name", "")
        if tool_name not in {"Write", "Edit", "MultiEdit"}:
            return HookResult(False, f"ignored tool: {tool_name}")
        file_path = payload.get("tool_input", {}).get("file_path", "")
        if not file_path:
            return HookResult(False, "missing file path")
        path = Path(file_path)
        if not path.is_absolute():
            path = self.project_root / path
        if path.suffix not in self._allowed_extensions():
            return HookResult(False, f"extension not reviewable: {path.suffix}")
        detail = self._change_detail(payload)
        min_lines = int(self.config.get("hook_mode", {}).get("min_lines_changed", 10))
        if tool_name == "Write" and detail.count("\n") < min_lines:
            return HookResult(False, "below minimum changed lines")
        self._append_pending(path, tool_name, detail)
        batch_ready = self._increment_counter() >= int(self.config.get("hook_mode", {}).get("batch_size", 5))
        self.trace.record("hook_change", tool=tool_name, file=str(path), batch_ready=batch_ready)
        return HookResult(True, "queued", batch_ready=batch_ready)

    def _normalize_hook_payload(self, payload: Dict[str, Any]) -> Dict[str, Any]:
        if "tool_name" in payload:
            return payload
        gemini_tool = payload.get("toolName", "")
        gemini_path = payload.get("toolInput", {}).get("path") or payload.get("toolInput", {}).get("file_path")
        if not gemini_tool or not gemini_path:
            return payload
        mapped_tool = {
            "write_file": "Write",
            "replace_in_file": "Edit",
            "patch": "Edit",
        }.get(gemini_tool, gemini_tool)
        return {"tool_name": mapped_tool, "tool_input": {"file_path": gemini_path, "content": payload.get("toolOutput", "")}}

    def _allowed_extensions(self) -> set[str]:
        configured = self.config.get("review", {}).get("file_extensions") or []
        if not configured:
            return DEFAULT_EXTENSIONS
        return {ext if ext.startswith(".") else f".{ext}" for ext in configured}

    def _change_detail(self, payload: Dict[str, Any]) -> str:
        tool_input = payload.get("tool_input", {})
        if payload.get("tool_name") == "Write":
            return str(tool_input.get("content", ""))
        if payload.get("tool_name") == "Edit":
            return "--- OLD ---\n{}\n--- NEW ---\n{}".format(tool_input.get("old_string", ""), tool_input.get("new_string", ""))
        edits = tool_input.get("edits", []) or []
        return "\n".join("--- OLD ---\n{}\n--- NEW ---\n{}".format(edit.get("old_string", ""), edit.get("new_string", "")) for edit in edits)

    def _append_pending(self, path: Path, tool_name: str, detail: str) -> None:
        pending = self.session_dir / "pending-changes.jsonl"
        row = {"ts": time.time(), "file": str(path), "tool": tool_name, "detail": detail}
        with pending.open("a", encoding="utf-8") as handle:
            handle.write(json.dumps(row, sort_keys=True, separators=(",", ":")) + "\n")

    def _increment_counter(self) -> int:
        counter = self.session_dir / "change-counter"
        try:
            value = int(counter.read_text(encoding="utf-8").strip() or "0")
        except FileNotFoundError:
            value = 0
        value += 1
        counter.write_text(str(value), encoding="utf-8")
        return value


def default_session_dir(project_root: Path) -> Path:
    import hashlib

    digest = hashlib.sha256(str(project_root).encode("utf-8")).hexdigest()[:12]
    return Path(os.environ.get("TMPDIR", "/tmp")) / f"ai-review-arena-{digest}"


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="arena-runtime")
    sub = parser.add_subparsers(dest="command", required=True)
    hook = sub.add_parser("hook-post-tool-use")
    hook.add_argument("--config", default="config/default-config.json")
    hook.add_argument("--project-root", default=os.getcwd())
    hook.add_argument("--session-dir", default="")
    args = parser.parse_args(argv)

    if args.command == "hook-post-tool-use":
        try:
            payload = json.loads(sys.stdin.read() or "{}")
            project_root = Path(args.project_root).resolve()
            config_path = Path(args.config)
            if not config_path.is_absolute():
                config_path = project_root / config_path
            config = load_json_config(config_path)
            session_dir = Path(args.session_dir) if args.session_dir else default_session_dir(project_root)
            result = HookOrchestrator(project_root, config, session_dir).handle_post_tool_use(payload)
            print(json.dumps(result.to_dict(), sort_keys=True))
        except Exception as exc:
            print(json.dumps({"accepted": False, "reason": f"runtime error: {exc}", "batch_ready": False}, sort_keys=True), file=sys.stderr)
        return 0
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
