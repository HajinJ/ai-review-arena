# Production Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move AI Review Arena from internal CLI harness to externally installable production-grade CLI tool.

**Architecture:** Keep the existing CLI-first Python runtime. Add product hardening around provider readiness, MCP security boundaries, package metadata, CI/CD, OTel collector smoke, RAG semantic scoring, dashboard generation, and onboarding docs.

**Tech Stack:** Python 3.10+, setuptools, GitHub Actions, Docker-based OpenTelemetry Collector smoke, local deterministic semantic hash vectors, static HTML dashboard.

---

### Task 1: Packaging and CLI

**Files:** `pyproject.toml`

Add package metadata, `arena` console script, build backend, optional extras, and semantic version `0.2.0`.

### Task 2: Provider readiness

**Files:** `arena_runtime/provider_runner.py`, `arena_runtime/benchmarking.py`, `arena_runtime/entrypoint.py`

Add `provider-smoke`, classify auth/interactive/timeout/non-json failures, include Claude CLI diagnostics, and add `--require-live-success` to live benchmarks.

### Task 3: MCP hardening

**Files:** `arena_runtime/mcp_runtime.py`, `config/default-config.json`

Add command allowlist, cwd root restriction, env allowlist, secret env exclusion, stdout/stderr size caps, secret redaction, and elapsed-time telemetry.

### Task 4: RAG semantic backend

**Files:** `arena_runtime/semantic_backends.py`, `arena_runtime/rag_runtime.py`, `arena_runtime/domain_runtime.py`

Add optional local deterministic semantic hash vectors and semantic ranking metadata without introducing network dependencies.

### Task 5: Dashboard and dogfood

**Files:** `arena_runtime/dashboard.py`, `.github/workflows/nightly-dogfood.yml`

Generate a static HTML dashboard from harness events and benchmark JSON. Run nightly deterministic dogfood and upload dashboard artifact.

### Task 6: CI/CD hardening

**Files:** `.github/workflows/test.yml`, `.github/workflows/release.yml`, `config/otel-collector.yml`

Run Python matrix, package install/build, JSON validation, shellcheck, unit/integration tests, deterministic benchmarks, MCP stdio smoke, OTel collector smoke, and dashboard artifact upload.

### Task 7: Tests and docs

**Files:** `tests/unit/test-production-hardening.sh`, `tests/integration/test-otel-collector.sh`, docs under `docs/`

Add smoke tests for provider readiness JSON, MCP boundary behavior, semantic RAG metadata, dashboard output, and OTel collector integration. Add external onboarding docs.
