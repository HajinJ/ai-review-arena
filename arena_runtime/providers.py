from __future__ import annotations

import os
import shlex
import subprocess
import time
from collections.abc import Mapping
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Sequence, Tuple

from .observability import TraceLogger, redact_text
from .policy import RuntimePolicy
from .schemas import ProviderResponse

DEFAULT_CLI_ENV_ALLOWLIST: Tuple[str, ...] = (
    "PATH",
    "HOME",
    "TMPDIR",
    "TEMP",
    "LANG",
    "LC_ALL",
    "SHELL",
    "USER",
    "CODEX_HOME",
    "CLAUDE_CONFIG_DIR",
    "GEMINI_CONFIG_DIR",
    "XDG_CONFIG_HOME",
    "XDG_CACHE_HOME",
)


@dataclass(frozen=True)
class ModelSelection:
    use_user_default: bool = True
    model_variant: str = ""
    recommended_model_variant: str = ""


@dataclass(frozen=True)
class CLIProviderConfig:
    provider: str
    command: Tuple[str, ...]
    model_selection: ModelSelection = field(default_factory=ModelSelection)
    timeout_seconds: int = 120
    cwd: Optional[Path] = None
    prompt_transport: str = "argument"
    env_allowlist: Tuple[str, ...] = DEFAULT_CLI_ENV_ALLOWLIST
    required_env: Tuple[str, ...] = ()
    allowed_exit_codes: Tuple[int, ...] = (0,)
    structured_output: bool = False
    schema_path: str = ""


def provider_model_args(provider: str, selection: ModelSelection) -> List[str]:
    if selection.use_user_default or not selection.model_variant:
        return []
    if provider == "codex":
        return ["-m", selection.model_variant]
    if provider == "gemini":
        return ["--model", selection.model_variant]
    if provider == "claude":
        return ["--model", selection.model_variant]
    return []


def parse_command(command: str | Sequence[str]) -> List[str]:
    if isinstance(command, str):
        parsed = shlex.split(command)
    else:
        parsed = [str(part) for part in command]
    if not parsed:
        raise ProviderError("CLI command is empty")
    return parsed


def build_cli_provider(
    provider: str,
    config: Mapping[str, Any],
    *,
    trace: Optional[TraceLogger] = None,
    project_root: Optional[Path] = None,
    policy: Optional[RuntimePolicy] = None,
) -> "CLIProvider":
    command = parse_command(str(config.get("command") or provider))
    selection = ModelSelection(
        use_user_default=bool(config.get("use_user_default", True)),
        model_variant=str(config.get("model_variant", "") or ""),
        recommended_model_variant=str(config.get("recommended_model_variant", "") or ""),
    )
    runtime_cfg = config.get("runtime", {}) if isinstance(config.get("runtime", {}), Mapping) else {}
    env_allowlist = tuple(runtime_cfg.get("env_passthrough", DEFAULT_CLI_ENV_ALLOWLIST))
    provider_cfg = CLIProviderConfig(
        provider=provider,
        command=tuple(command + provider_model_args(provider, selection)),
        model_selection=selection,
        timeout_seconds=int(config.get("timeout_seconds", runtime_cfg.get("default_timeout_seconds", 120))),
        cwd=project_root,
        prompt_transport=str(config.get("prompt_transport", runtime_cfg.get("prompt_transport", "argument"))),
        env_allowlist=env_allowlist,
        required_env=tuple(config.get("required_env", ())),
        structured_output=bool(config.get("structured_output", False)),
        schema_path=str(config.get("schema_path", "") or ""),
    )
    return CLIProvider(provider_cfg, trace=trace, policy=policy)


class ProviderError(RuntimeError):
    pass


class BaseProvider:
    name = "base"

    def __init__(self, model: str = "", trace: Optional[TraceLogger] = None) -> None:
        self.model = model
        self.trace = trace

    def generate(self, prompt: str, *, schema: Optional[Dict[str, Any]] = None) -> ProviderResponse:
        raise NotImplementedError

    def _record(self, response: ProviderResponse) -> ProviderResponse:
        if self.trace:
            self.trace.record(
                "model_call",
                provider=response.provider,
                model=response.model or "user-default",
                latency_ms=response.latency_ms,
                cost_usd=response.cost_usd,
                tool_call_count=len(response.tool_calls),
            )
        return response


class CLIProvider(BaseProvider):
    def __init__(self, config: CLIProviderConfig, trace: Optional[TraceLogger] = None, policy: Optional[RuntimePolicy] = None) -> None:
        model = config.model_selection.model_variant if not config.model_selection.use_user_default else ""
        super().__init__(model=model, trace=trace)
        self.name = config.provider
        self.config = config
        self.policy = policy

    @property
    def command(self) -> List[str]:
        return list(self.config.command)

    def generate(self, prompt: str, *, schema: Optional[Dict[str, Any]] = None) -> ProviderResponse:
        command = self.command
        if self.policy:
            decision = self.policy.authorize_command(command)
            if not decision.allowed:
                raise ProviderError(decision.reason)
            credential_decision = self.policy.authorize_credentials(self.name, os.environ)
            if not credential_decision.allowed:
                raise ProviderError(credential_decision.reason)

        env = self._build_env(os.environ)
        for required in self.config.required_env:
            if not env.get(required):
                raise ProviderError(f"missing required CLI environment variable for {self.name}: {required}")

        run_command = command if self.config.prompt_transport == "stdin" else command + [prompt]
        run_input = prompt if self.config.prompt_transport == "stdin" else None
        started = time.time()
        try:
            proc = subprocess.run(
                run_command,
                input=run_input,
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                cwd=str(self.config.cwd) if self.config.cwd else None,
                env=env,
                timeout=self.config.timeout_seconds,
                check=False,
            )
            latency = int((time.time() - started) * 1000)
        except subprocess.TimeoutExpired as exc:
            latency = int((time.time() - started) * 1000)
            self._record_cli(exit_code=None, latency_ms=latency, stdout="", stderr=str(exc), timed_out=True, schema_requested=bool(schema))
            raise ProviderError(f"{self.name} CLI timed out after {self.config.timeout_seconds}s") from exc

        self._record_cli(
            exit_code=proc.returncode,
            latency_ms=latency,
            stdout=proc.stdout,
            stderr=proc.stderr,
            timed_out=False,
            schema_requested=bool(schema),
        )
        if proc.returncode not in self.config.allowed_exit_codes:
            detail = redact_text(proc.stderr.strip() or f"{self.name} CLI exited {proc.returncode}")
            raise ProviderError(detail)
        return self._record(
            ProviderResponse(
                self.name,
                self.model or "user-default",
                proc.stdout,
                latency_ms=latency,
                raw={
                    "exit_code": proc.returncode,
                    "stderr": redact_text(proc.stderr),
                    "structured_output": self.config.structured_output,
                    "schema_path": self.config.schema_path,
                },
            )
        )

    def _build_env(self, source: Mapping[str, str]) -> Dict[str, str]:
        return {key: value for key, value in source.items() if key in self.config.env_allowlist}

    def _record_cli(self, *, exit_code: Optional[int], latency_ms: int, stdout: str, stderr: str, timed_out: bool, schema_requested: bool) -> None:
        if not self.trace:
            return
        self.trace.record_cli_call(
            provider=self.name,
            command=self.command,
            model=self.model or "user-default",
            exit_code=exit_code,
            latency_ms=latency_ms,
            stdout_bytes=len(stdout.encode("utf-8", errors="replace")),
            stderr_bytes=len(stderr.encode("utf-8", errors="replace")),
            timed_out=timed_out,
            structured_output=self.config.structured_output,
            schema_requested=schema_requested,
        )
