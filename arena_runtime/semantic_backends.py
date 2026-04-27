from __future__ import annotations

import hashlib
import math
import re
from typing import Sequence

TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_]{2,}")


def token_hash_vector(text: str, *, dims: int = 128) -> list[float]:
    dims = max(16, min(4096, int(dims or 128)))
    vector = [0.0] * dims
    for token in TOKEN_RE.findall(text.lower()):
        digest = hashlib.blake2b(token.encode("utf-8"), digest_size=8).digest()
        raw = int.from_bytes(digest, "big")
        index = raw % dims
        sign = -1.0 if raw & 1 else 1.0
        vector[index] += sign
    norm = math.sqrt(sum(value * value for value in vector)) or 1.0
    return [round(value / norm, 6) for value in vector]


def cosine_similarity(left: Sequence[float], right: Sequence[float]) -> float:
    if not left or not right:
        return 0.0
    limit = min(len(left), len(right))
    numerator = sum(float(left[idx]) * float(right[idx]) for idx in range(limit))
    left_norm = math.sqrt(sum(float(value) * float(value) for value in left[:limit])) or 1.0
    right_norm = math.sqrt(sum(float(value) * float(value) for value in right[:limit])) or 1.0
    return round(numerator / (left_norm * right_norm), 6)


def semantic_backend_name(configured: str | None) -> str:
    value = str(configured or "local-hash").strip().lower()
    if value in {"", "none", "off", "disabled", "false"}:
        return "disabled"
    if value in {"local", "local-hash", "hash", "local-hash-v1"}:
        return "local-hash-v1"
    return value
