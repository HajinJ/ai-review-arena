from __future__ import annotations

import difflib
from dataclasses import dataclass
from pathlib import Path

from .harness import HarnessRun


@dataclass(frozen=True)
class AutoFixPolicy:
    enabled: bool = False
    require_human_approval: bool = True


@dataclass(frozen=True)
class PatchPreparation:
    allowed: bool
    reason: str
    patch_path: Path


def prepare_isolated_patch(target: Path, new_content: str, policy: AutoFixPolicy, *, approved: bool = False) -> PatchPreparation:
    target = Path(target)
    harness = HarnessRun.from_env(target.parent if target.parent.exists() else None)
    harness.emit("autofix.patch_requested", phase="autofix", target=str(target), enabled=policy.enabled, approved=approved)
    patch_path = target.with_suffix(target.suffix + ".arena.patch")
    if not policy.enabled:
        harness.emit("autofix.patch_blocked", phase="autofix", target=str(target), reason="auto-fix disabled")
        return PatchPreparation(False, "auto-fix disabled", patch_path)
    if policy.require_human_approval and not approved:
        harness.emit("autofix.patch_blocked", phase="autofix", target=str(target), reason="human approval required")
        return PatchPreparation(False, "human approval required", patch_path)
    old_content = target.read_text(encoding="utf-8")
    diff = difflib.unified_diff(
        old_content.splitlines(keepends=True),
        new_content.splitlines(keepends=True),
        fromfile=str(target),
        tofile=str(target) + ".candidate",
    )
    patch_path.write_text("".join(diff), encoding="utf-8")
    harness.emit("autofix.patch_created", phase="autofix", target=str(target), patch_path=str(patch_path))
    return PatchPreparation(True, "patch artifact created", patch_path)
