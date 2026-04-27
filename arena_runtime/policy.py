from __future__ import annotations

import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, Mapping, Optional, Sequence, Set


@dataclass(frozen=True)
class ApprovalDecision:
    approved: bool = False
    approver: str = ""
    reason: str = ""


@dataclass(frozen=True)
class ToolRequest:
    name: str
    side_effect: bool = False
    approval: Optional[ApprovalDecision] = None


@dataclass(frozen=True)
class PolicyResult:
    allowed: bool
    reason: str = ""


@dataclass
class RuntimePolicy:
    allowed_tools: Set[str] = field(default_factory=set)
    side_effect_tools: Set[str] = field(default_factory=set)
    credential_scopes: Dict[str, Set[str]] = field(default_factory=dict)
    allowed_commands: Set[str] = field(default_factory=set)
    write_roots: Set[str] = field(default_factory=set)
    allowed_mcp_tools: Set[str] = field(default_factory=set)
    side_effect_mcp_tools: Set[str] = field(default_factory=set)
    rag_block_prompt_injection: bool = False

    def authorize_tool(self, request: ToolRequest) -> PolicyResult:
        if not self.allowed_tools or request.name not in self.allowed_tools:
            return PolicyResult(False, f"tool not allowlisted: {request.name}")
        is_side_effect = request.side_effect or request.name in self.side_effect_tools
        if is_side_effect and not (request.approval and request.approval.approved):
            return PolicyResult(False, f"tool requires approval: {request.name}")
        return PolicyResult(True, "allowed")

    def authorize_command(self, command: Sequence[str]) -> PolicyResult:
        if not command:
            return PolicyResult(False, "empty command")
        executable = Path(command[0]).name
        if not self.allowed_commands or executable not in self.allowed_commands:
            return PolicyResult(False, f"command not allowlisted: {executable}")
        if any("\x00" in str(part) for part in command):
            return PolicyResult(False, "command contains NUL byte")
        return PolicyResult(True, "allowed")

    def authorize_credentials(self, provider: str, env: Mapping[str, str]) -> PolicyResult:
        required = self.credential_scopes.get(provider, set())
        missing = sorted(name for name in required if not env.get(name))
        if missing:
            return PolicyResult(False, f"missing scoped credentials for {provider}: {', '.join(missing)}")
        return PolicyResult(True, "allowed")

    def authorize_mcp_tool(self, server: str, tool: str, *, side_effect: bool = False, approval: Optional[ApprovalDecision] = None) -> PolicyResult:
        qualified = f"{server}.{tool}" if server else tool
        allowed_names = {qualified, tool}
        if self.allowed_mcp_tools and not (self.allowed_mcp_tools & allowed_names):
            return PolicyResult(False, f"MCP tool not allowlisted: {qualified}")
        is_side_effect = side_effect or bool(self.side_effect_mcp_tools & allowed_names)
        if is_side_effect and not (approval and approval.approved):
            return PolicyResult(False, f"MCP tool requires approval: {qualified}")
        return PolicyResult(True, "allowed")

    def inspect_rag_context(self, text: str, *, source: str = "rag") -> PolicyResult:
        boundary = inspect_untrusted_text(text, source=source)
        if self.rag_block_prompt_injection and boundary.get("blocked"):
            return PolicyResult(False, f"blocked untrusted context: {', '.join(boundary.get('flags', []))}")
        return PolicyResult(True, "allowed")

    def authorize_write_path(self, path: str | os.PathLike[str]) -> PolicyResult:
        if not self.write_roots:
            return PolicyResult(True, "allowed")
        resolved = Path(path).resolve()
        for root in self.write_roots:
            root_path = Path(root).resolve()
            try:
                resolved.relative_to(root_path)
                return PolicyResult(True, "allowed")
            except ValueError:
                continue
        return PolicyResult(False, f"write path outside allowed roots: {resolved}")


PROMPT_INJECTION_PATTERNS: tuple[tuple[str, re.Pattern[str]], ...] = (
    ("ignore_previous_instructions", re.compile(r"\b(ignore|forget|override)\b.{0,80}\b(previous|system|developer|above)\b.{0,40}\binstructions?\b", re.IGNORECASE | re.DOTALL)),
    ("tool_or_secret_request", re.compile(r"\b(reveal|print|show|send|post|upload|exfiltrate|leak|copy|dump|read)\b.{0,80}\b(api[_ -]?key|token|password|secret|credential|private key)\b", re.IGNORECASE | re.DOTALL)),
    ("exfiltration_request", re.compile(r"\b(send|post|upload|exfiltrate|leak)\b.{0,80}\b(secret|token|credential|env|environment)\b", re.IGNORECASE | re.DOTALL)),
    ("agent_control_request", re.compile(r"\b(call|use|run|execute)\b.{0,80}\b(tool|bash|shell|mcp|command)\b", re.IGNORECASE | re.DOTALL)),
)


def inspect_untrusted_text(text: str, *, source: str = "untrusted") -> Dict[str, Any]:
    flags = [name for name, pattern in PROMPT_INJECTION_PATTERNS if pattern.search(text or "")]
    return {
        "source": source,
        "trusted": False,
        "blocked": bool(flags),
        "flags": flags,
        "policy": "treat_as_data_never_instructions",
    }
