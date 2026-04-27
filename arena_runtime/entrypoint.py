from __future__ import annotations

import sys

from arena_runtime.benchmarking import (
    cmd_benchmark_harness_ablation,
    cmd_benchmark_models,
    cmd_benchmark_score,
    cmd_retrieval_benchmark,
    cmd_run_benchmark,
    cmd_run_solo_benchmark,
)
from arena_runtime.cli_ports import main as ports_main
from arena_runtime.core_cli import main as core_main
from arena_runtime.domain_runtime import (
    cmd_content_review,
    cmd_domain_benchmark,
    cmd_legacy_inventory,
    cmd_rag_indexer,
    cmd_rag_retrieve,
    cmd_validate_doc_consistency,
)
from arena_runtime.dashboard import cmd_dashboard_build
from arena_runtime.legacy_ports import (
    cmd_batch_worktree_review,
    cmd_codex_batch_review,
    cmd_cross_examine,
    cmd_doc_inventory,
    cmd_harness_stress_test,
    cmd_ralph_loop,
    cmd_review_daemon,
    cmd_search_best_practices,
    cmd_search_guidelines,
    cmd_stream_monitor,
    cmd_stream_orchestrator,
)
from arena_runtime.exporters import cmd_export_extension, cmd_install_claude_integration
from arena_runtime.harness import cmd_harness_event, cmd_otel_export, cmd_otel_push
from arena_runtime.mcp_runtime import cmd_mcp_stdio_server, cmd_mcp_tool_call
from arena_runtime.orchestrator import main as orchestrator_main
from arena_runtime.provider_runner import cmd_cli_diagnostics, cmd_provider_smoke, cmd_review_provider
from arena_runtime.rag_runtime import cmd_rag_evidence
from arena_runtime.support_runtime import cmd_benchmark_utils, cmd_setup, cmd_setup_arena, cmd_support_utils

CORE_COMMANDS = {"normalize-severity", "validate-config", "aggregate-findings", "generate-report", "validate-provider-output"}
PORTED_COMMANDS = {
    "run-debate",
    "cost-estimator",
    "escalation-scan",
    "normalize-scanner-output",
    "cache-manager",
    "feedback-tracker",
    "detect-stack",
    "context-filter",
    "signal-log",
    "auto-tune-prompts",
    "evaluate-pipeline",
    "review-gate",
    "static-analysis",
}
DIRECT_COMMANDS = {
    "benchmark-score",
    "run-benchmark",
    "run-solo-benchmark",
    "benchmark-models",
    "retrieval-benchmark",
    "benchmark-harness-ablation",
    "codex-review",
    "gemini-review",
    "codex-doc-review",
    "gemini-doc-review",
    "codex-business-review",
    "gemini-business-review",
    "benchmark-doc-models",
    "benchmark-business-models",
    "rag-indexer",
    "rag-retrieve",
    "rag-evidence",
    "validate-doc-consistency",
    "harness-event",
    "otel-export",
    "otel-push",
    "export-extension",
    "install-claude-integration",
    "mcp-tool-call",
    "mcp-stdio-server",
    "legacy-inventory",
    "cli-diagnostics",
    "provider-smoke",
    "dashboard-build",
    "batch-worktree-review",
    "codex-batch-review",
    "codex-cross-examine",
    "doc-inventory",
    "gemini-cross-examine",
    "harness-stress-test",
    "ralph-loop",
    "review-daemon",
    "search-best-practices",
    "search-guidelines",
    "stream-monitor",
    "stream-orchestrator",
    "support-utils",
    "benchmark-utils",
    "setup",
    "setup-arena",
}


def main(argv: list[str] | None = None) -> int:
    args = list(sys.argv[1:] if argv is None else argv)
    if args and args[0] in CORE_COMMANDS:
        return core_main(args)
    if args and args[0] in PORTED_COMMANDS:
        return ports_main(args)
    if args and args[0] in DIRECT_COMMANDS:
        command, rest = args[0], args[1:]
        if command == "benchmark-score":
            return cmd_benchmark_score(rest)
        if command == "run-benchmark":
            return cmd_run_benchmark(rest)
        if command == "run-solo-benchmark":
            return cmd_run_solo_benchmark(rest)
        if command == "benchmark-models":
            return cmd_benchmark_models(rest)
        if command == "retrieval-benchmark":
            return cmd_retrieval_benchmark(rest)
        if command == "benchmark-harness-ablation":
            return cmd_benchmark_harness_ablation(rest)
        if command == "codex-review":
            return cmd_review_provider("codex", rest)
        if command == "gemini-review":
            return cmd_review_provider("gemini", rest)
        if command == "codex-doc-review":
            return cmd_content_review("doc", "codex", rest)
        if command == "gemini-doc-review":
            return cmd_content_review("doc", "gemini", rest)
        if command == "codex-business-review":
            return cmd_content_review("business", "codex", rest)
        if command == "gemini-business-review":
            return cmd_content_review("business", "gemini", rest)
        if command == "benchmark-doc-models":
            return cmd_domain_benchmark("doc", rest)
        if command == "benchmark-business-models":
            return cmd_domain_benchmark("business", rest)
        if command == "rag-indexer":
            return cmd_rag_indexer(rest)
        if command == "rag-retrieve":
            return cmd_rag_retrieve(rest)
        if command == "rag-evidence":
            return cmd_rag_evidence(rest)
        if command == "validate-doc-consistency":
            return cmd_validate_doc_consistency(rest)
        if command == "harness-event":
            return cmd_harness_event(rest)
        if command == "otel-export":
            return cmd_otel_export(rest)
        if command == "otel-push":
            return cmd_otel_push(rest)
        if command == "export-extension":
            return cmd_export_extension(rest)
        if command == "install-claude-integration":
            return cmd_install_claude_integration(rest)
        if command == "mcp-tool-call":
            return cmd_mcp_tool_call(rest)
        if command == "mcp-stdio-server":
            return cmd_mcp_stdio_server(rest)
        if command == "legacy-inventory":
            return cmd_legacy_inventory(rest)
        if command == "cli-diagnostics":
            return cmd_cli_diagnostics(rest)
        if command == "provider-smoke":
            return cmd_provider_smoke(rest)
        if command == "dashboard-build":
            return cmd_dashboard_build(rest)
        if command == "batch-worktree-review":
            return cmd_batch_worktree_review(rest)
        if command == "codex-batch-review":
            return cmd_codex_batch_review(rest)
        if command == "codex-cross-examine":
            return cmd_cross_examine("codex", rest)
        if command == "doc-inventory":
            return cmd_doc_inventory(rest)
        if command == "gemini-cross-examine":
            return cmd_cross_examine("gemini", rest)
        if command == "harness-stress-test":
            return cmd_harness_stress_test(rest)
        if command == "ralph-loop":
            return cmd_ralph_loop(rest)
        if command == "review-daemon":
            return cmd_review_daemon(rest)
        if command == "search-best-practices":
            return cmd_search_best_practices(rest)
        if command == "search-guidelines":
            return cmd_search_guidelines(rest)
        if command == "stream-monitor":
            return cmd_stream_monitor(rest)
        if command == "stream-orchestrator":
            return cmd_stream_orchestrator(rest)
        if command == "support-utils":
            return cmd_support_utils(rest)
        if command == "benchmark-utils":
            return cmd_benchmark_utils(rest)
        if command == "setup":
            return cmd_setup(rest)
        if command == "setup-arena":
            return cmd_setup_arena(rest)
    return orchestrator_main()
