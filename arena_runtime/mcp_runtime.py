from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Mapping, Sequence

from .harness import HarnessRun
from .policy import ApprovalDecision, RuntimePolicy


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _load_json_safe(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except Exception:
        return {}


def _mcp_cfg(config: Mapping[str, Any]) -> dict[str, Any]:
    return config.get("mcp", {}) if isinstance(config.get("mcp"), dict) else {}


def _tool_cfg(cfg: Mapping[str, Any], server: str, tool: str) -> dict[str, Any]:
    servers = cfg.get("servers", {}) if isinstance(cfg.get("servers"), dict) else {}
    server_cfg = servers.get(server, {}) if isinstance(servers.get(server), dict) else {}
    tools = server_cfg.get("tools", {}) if isinstance(server_cfg.get("tools"), dict) else {}
    return tools.get(tool, {}) if isinstance(tools.get(tool), dict) else {}


def _policy_from_config(cfg: Mapping[str, Any]) -> RuntimePolicy:
    allowed = {str(item) for item in cfg.get("allowed_tools", []) if str(item).strip()} if isinstance(cfg.get("allowed_tools"), list) else set()
    side_effect = {str(item) for item in cfg.get("side_effect_tools", []) if str(item).strip()} if isinstance(cfg.get("side_effect_tools"), list) else set()
    return RuntimePolicy(allowed_mcp_tools=allowed, side_effect_mcp_tools=side_effect)


def _run_configured_tool(
    config: Mapping[str, Any],
    *,
    server: str,
    tool: str,
    input_data: Any,
    approved: bool = False,
    dry_run: bool = False,
    timeout: int = 30,
) -> dict[str, Any]:
    mcp_cfg = _mcp_cfg(config)
    tool_cfg = _tool_cfg(mcp_cfg, server, tool)
    side_effect = bool(tool_cfg.get("side_effect", False))
    policy = _policy_from_config(mcp_cfg)
    decision = policy.authorize_mcp_tool(
        server,
        tool,
        side_effect=side_effect,
        approval=ApprovalDecision(approved=approved, approver="cli", reason="approved runtime flag"),
    )
    harness = HarnessRun.from_env()
    harness.emit("mcp.tool_requested", phase="mcp", server=server, tool=tool, side_effect=side_effect, approved=approved)
    if not decision.allowed:
        harness.emit("mcp.tool_blocked", phase="mcp", server=server, tool=tool, reason=decision.reason)
        return {"allowed": False, "reason": decision.reason}

    command = tool_cfg.get("command", [])
    if isinstance(command, str):
        command = [command]
    if not isinstance(command, list) or not command:
        harness.emit("mcp.tool_blocked", phase="mcp", server=server, tool=tool, reason="tool command not configured")
        return {"allowed": False, "reason": "tool command not configured"}
    command = [str(part) for part in command]

    if dry_run:
        return {"allowed": True, "dry_run": True, "server": server, "tool": tool, "command": command}

    completed = subprocess.run(
        command,
        input=json.dumps(input_data, ensure_ascii=False),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env={key: value for key, value in os.environ.items() if key in {"PATH", "HOME", "TMPDIR", "LANG", "LC_ALL"}},
        timeout=max(1, timeout),
        check=False,
    )
    harness.emit(
        "mcp.tool_completed",
        phase="mcp",
        server=server,
        tool=tool,
        exit_code=completed.returncode,
        stdout_bytes=len(completed.stdout.encode()),
        stderr_bytes=len(completed.stderr.encode()),
    )
    return {
        "allowed": True,
        "server": server,
        "tool": tool,
        "exit_code": completed.returncode,
        "stdout": completed.stdout,
        "stderr": completed.stderr,
    }


def cmd_mcp_tool_call(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="mcp-tool-call")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--server", required=True)
    parser.add_argument("--tool", required=True)
    parser.add_argument("--input-json", default="{}")
    parser.add_argument("--approved", action="store_true")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args(list(argv))

    config = _load_json_safe(Path(args.config))
    try:
        parsed_input = json.loads(args.input_json)
    except json.JSONDecodeError:
        parsed_input = {"raw": args.input_json}
    result = _run_configured_tool(
        config,
        server=args.server,
        tool=args.tool,
        input_data=parsed_input,
        approved=args.approved,
        dry_run=args.dry_run,
        timeout=args.timeout,
    )
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


def _jsonrpc_result(request_id: Any, result: Mapping[str, Any]) -> dict[str, Any]:
    return {"jsonrpc": "2.0", "id": request_id, "result": dict(result)}


def _jsonrpc_error(request_id: Any, code: int, message: str, data: Any | None = None) -> dict[str, Any]:
    payload: dict[str, Any] = {"jsonrpc": "2.0", "id": request_id, "error": {"code": code, "message": message}}
    if data is not None:
        payload["error"]["data"] = data
    return payload


def _configured_tools(config: Mapping[str, Any]) -> list[dict[str, Any]]:
    mcp_cfg = _mcp_cfg(config)
    servers = mcp_cfg.get("servers", {}) if isinstance(mcp_cfg.get("servers"), dict) else {}
    tools: list[dict[str, Any]] = []
    for server_name, server_cfg in sorted(servers.items()):
        if not isinstance(server_cfg, dict):
            continue
        server_tools = server_cfg.get("tools", {}) if isinstance(server_cfg.get("tools"), dict) else {}
        for tool_name, tool_cfg in sorted(server_tools.items()):
            if not isinstance(tool_cfg, dict):
                continue
            qualified = f"{server_name}.{tool_name}"
            tools.append(
                {
                    "name": qualified,
                    "description": str(tool_cfg.get("description") or f"{qualified} command adapter"),
                    "inputSchema": tool_cfg.get("input_schema") if isinstance(tool_cfg.get("input_schema"), dict) else {"type": "object"},
                }
            )
    return tools


def _split_tool_name(config: Mapping[str, Any], name: str) -> tuple[str, str] | None:
    if "." in name:
        server, tool = name.split(".", 1)
        return (server, tool) if server and tool else None
    mcp_cfg = _mcp_cfg(config)
    servers = mcp_cfg.get("servers", {}) if isinstance(mcp_cfg.get("servers"), dict) else {}
    matches: list[tuple[str, str]] = []
    for server_name, server_cfg in servers.items():
        if not isinstance(server_cfg, dict):
            continue
        tools = server_cfg.get("tools", {}) if isinstance(server_cfg.get("tools"), dict) else {}
        if name in tools:
            matches.append((str(server_name), name))
    return matches[0] if len(matches) == 1 else None


def _handle_mcp_message(config: Mapping[str, Any], message: Mapping[str, Any], *, approved: bool, timeout: int) -> dict[str, Any] | None:
    request_id = message.get("id")
    method = str(message.get("method") or "")
    if not method:
        return _jsonrpc_error(request_id, -32600, "missing method")
    if request_id is None and method.startswith("notifications/"):
        return None

    if method == "initialize":
        return _jsonrpc_result(
            request_id,
            {
                "protocolVersion": "2024-11-05",
                "capabilities": {"tools": {"listChanged": False}, "resources": {}, "prompts": {}},
                "serverInfo": {"name": "ai-review-arena", "version": "0.1.0"},
            },
        )
    if method == "ping":
        return _jsonrpc_result(request_id, {})
    if method == "tools/list":
        return _jsonrpc_result(request_id, {"tools": _configured_tools(config)})
    if method == "resources/list":
        return _jsonrpc_result(request_id, {"resources": []})
    if method == "prompts/list":
        return _jsonrpc_result(request_id, {"prompts": []})
    if method == "tools/call":
        params = message.get("params", {})
        if not isinstance(params, dict):
            return _jsonrpc_error(request_id, -32602, "params must be an object")
        name = str(params.get("name") or "")
        split = _split_tool_name(config, name)
        if split is None:
            return _jsonrpc_error(request_id, -32602, f"unknown or ambiguous tool: {name}")
        arguments = params.get("arguments", {})
        if not isinstance(arguments, dict):
            return _jsonrpc_error(request_id, -32602, "arguments must be an object")
        server, tool = split
        result = _run_configured_tool(config, server=server, tool=tool, input_data=arguments, approved=approved, timeout=timeout)
        text = json.dumps(result, ensure_ascii=False, indent=2)
        return _jsonrpc_result(request_id, {"content": [{"type": "text", "text": text}], "isError": not bool(result.get("allowed")) or bool(result.get("exit_code"))})
    return _jsonrpc_error(request_id, -32601, f"method not found: {method}")


def cmd_mcp_stdio_server(argv: Sequence[str]) -> int:
    parser = argparse.ArgumentParser(prog="mcp-stdio-server")
    parser.add_argument("--config", default=str(_repo_root() / "config" / "default-config.json"))
    parser.add_argument("--approved", action="store_true", help="treat side-effect MCP tools as externally approved")
    parser.add_argument("--timeout", type=int, default=30)
    args = parser.parse_args(list(argv))

    config = _load_json_safe(Path(args.config))
    HarnessRun.from_env().emit("mcp.stdio_started", phase="mcp", config=str(args.config))
    for raw_line in sys.stdin:
        line = raw_line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except json.JSONDecodeError as exc:
            print(json.dumps(_jsonrpc_error(None, -32700, "parse error", str(exc)), ensure_ascii=False), flush=True)
            continue
        if not isinstance(message, dict):
            print(json.dumps(_jsonrpc_error(None, -32600, "request must be an object"), ensure_ascii=False), flush=True)
            continue
        try:
            response = _handle_mcp_message(config, message, approved=args.approved, timeout=args.timeout)
        except Exception as exc:
            response = _jsonrpc_error(message.get("id"), -32603, "internal error", str(exc))
        if response is not None:
            print(json.dumps(response, ensure_ascii=False), flush=True)
    HarnessRun.from_env().emit("mcp.stdio_stopped", phase="mcp")
    return 0
