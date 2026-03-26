#!/usr/bin/env bash
# =============================================================================
# harness-stress-test.sh — Phase ablation study for capability-relative harness
#
# Measures F1 score impact of disabling individual phases to determine which
# phases can be safely skipped for a given model without quality loss.
#
# Usage:
#   harness-stress-test.sh [--model <model>] [--phase <phase_to_test>] [--all]
#
# Options:
#   --model <model>     Model ID to test (default: current model from config)
#   --phase <phase>     Test a specific phase only (e.g., "5.8", "5.9")
#   --all               Test all skippable phases
#   --min-f1 <float>    Minimum F1 to consider phase skippable (default: 0.95)
#   --output <dir>      Output directory (default: cache/capability-tests)
#   --dry-run           Show what would be tested without running benchmarks
#
# Requires: run-benchmark.sh in the same scripts directory
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"

# Source utilities
source "${SCRIPT_DIR}/utils.sh" 2>/dev/null || true

# Defaults
MODEL=""
PHASE=""
TEST_ALL=false
MIN_F1=0.95
OUTPUT_DIR="${PLUGIN_DIR}/cache/capability-tests"
DRY_RUN=false

# Skippable phases (phases that can potentially be removed without F1 loss)
SKIPPABLE_PHASES=(
  "1"      # Stack Detection
  "2"      # Pre-Implementation Research
  "3"      # Compliance Detection
  "4"      # Model Benchmarking
  "5.5"    # Implementation Strategy
  "5.8"    # Static Analysis
  "5.9"    # Threat Modeling
  "6.6"    # Test Generation
  "6.7"    # Visual Verification
)

# --- Argument Parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --model)   MODEL="$2"; shift 2 ;;
    --phase)   PHASE="$2"; shift 2 ;;
    --all)     TEST_ALL=true; shift ;;
    --min-f1)  MIN_F1="$2"; shift 2 ;;
    --output)  OUTPUT_DIR="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    -h|--help)
      echo "Usage: harness-stress-test.sh [--model <model>] [--phase <phase>] [--all]"
      echo ""
      echo "Options:"
      echo "  --model <model>   Model ID to test (default: from config)"
      echo "  --phase <phase>   Test specific phase (e.g., 5.8, 5.9)"
      echo "  --all             Test all skippable phases"
      echo "  --min-f1 <float>  Min F1 to skip (default: 0.95)"
      echo "  --output <dir>    Output directory"
      echo "  --dry-run         Preview without running"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# --- Determine Model ---
if [ -z "$MODEL" ]; then
  MODEL=$(jq -r '.models.claude.agent_model // "sonnet"' "$CONFIG_FILE" 2>/dev/null || echo "sonnet")
fi

# --- Determine Phases to Test ---
PHASES_TO_TEST=()
if [ -n "$PHASE" ]; then
  PHASES_TO_TEST=("$PHASE")
elif [ "$TEST_ALL" = true ]; then
  PHASES_TO_TEST=("${SKIPPABLE_PHASES[@]}")
else
  echo "Error: Specify --phase <phase> or --all" >&2
  exit 1
fi

# --- Setup Output Directory ---
mkdir -p "$OUTPUT_DIR"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
RESULTS_FILE="${OUTPUT_DIR}/ablation-${MODEL}-${TIMESTAMP}.json"

echo "=== Harness Stress Test ==="
echo "Model:    $MODEL"
echo "Min F1:   $MIN_F1"
echo "Phases:   ${PHASES_TO_TEST[*]}"
echo "Output:   $RESULTS_FILE"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[DRY RUN] Would test the following phases:"
  for phase in "${PHASES_TO_TEST[@]}"; do
    echo "  - Phase $phase"
  done
  echo ""
  echo "[DRY RUN] Would run baseline benchmark first, then one benchmark per phase with that phase disabled."
  exit 0
fi

# --- Step 1: Baseline F1 Measurement ---
echo "--- Step 1: Baseline Benchmark ---"
BASELINE_OUTPUT="${OUTPUT_DIR}/baseline-${MODEL}-${TIMESTAMP}.json"

if [ -f "${SCRIPT_DIR}/run-benchmark.sh" ]; then
  bash "${SCRIPT_DIR}/run-benchmark.sh" --output "$BASELINE_OUTPUT" 2>/dev/null || {
    echo "Warning: Baseline benchmark failed. Using default F1=0.80" >&2
    echo '{"f1": 0.80, "precision": 0.80, "recall": 0.80}' > "$BASELINE_OUTPUT"
  }
else
  echo "Warning: run-benchmark.sh not found. Using default F1=0.80" >&2
  echo '{"f1": 0.80, "precision": 0.80, "recall": 0.80}' > "$BASELINE_OUTPUT"
fi

BASELINE_F1=$(jq -r '.f1 // 0.80' "$BASELINE_OUTPUT" 2>/dev/null || echo "0.80")
echo "Baseline F1: $BASELINE_F1"
echo ""

# --- Step 2: Phase Ablation ---
echo "--- Step 2: Phase Ablation ---"

RESULTS=()
SKIP_CANDIDATES=()

for phase in "${PHASES_TO_TEST[@]}"; do
  echo "Testing Phase $phase disabled..."

  PHASE_OUTPUT="${OUTPUT_DIR}/ablation-phase-${phase}-${MODEL}-${TIMESTAMP}.json"

  if [ -f "${SCRIPT_DIR}/run-benchmark.sh" ]; then
    bash "${SCRIPT_DIR}/run-benchmark.sh" \
      --skip-phase "$phase" \
      --output "$PHASE_OUTPUT" 2>/dev/null || {
      echo "  Warning: Benchmark with Phase $phase disabled failed" >&2
      echo "{\"f1\": 0.0, \"precision\": 0.0, \"recall\": 0.0, \"phase_disabled\": \"$phase\"}" > "$PHASE_OUTPUT"
    }
  else
    echo "  Warning: run-benchmark.sh not found, skipping" >&2
    echo "{\"f1\": 0.0, \"precision\": 0.0, \"recall\": 0.0, \"phase_disabled\": \"$phase\"}" > "$PHASE_OUTPUT"
  fi

  PHASE_F1=$(jq -r '.f1 // 0.0' "$PHASE_OUTPUT" 2>/dev/null || echo "0.0")
  F1_DELTA=$(echo "$BASELINE_F1 - $PHASE_F1" | bc -l 2>/dev/null || echo "999")
  F1_REMAINING=$(echo "$PHASE_F1" | bc -l 2>/dev/null || echo "0")

  SKIPPABLE="false"
  if (( $(echo "$PHASE_F1 >= $MIN_F1" | bc -l 2>/dev/null || echo 0) )); then
    SKIPPABLE="true"
    SKIP_CANDIDATES+=("$phase")
  fi

  RESULT="{\"phase\": \"$phase\", \"f1\": $PHASE_F1, \"f1_delta\": $F1_DELTA, \"skippable\": $SKIPPABLE}"
  RESULTS+=("$RESULT")

  echo "  Phase $phase: F1=$PHASE_F1 (delta=$F1_DELTA) skippable=$SKIPPABLE"
done

echo ""

# --- Step 3: Generate Results ---
echo "--- Step 3: Results ---"

# Build JSON array of results
RESULTS_JSON="["
for i in "${!RESULTS[@]}"; do
  if [ "$i" -gt 0 ]; then
    RESULTS_JSON+=","
  fi
  RESULTS_JSON+="${RESULTS[$i]}"
done
RESULTS_JSON+="]"

# Build skip candidates array
SKIP_JSON="["
for i in "${!SKIP_CANDIDATES[@]}"; do
  if [ "$i" -gt 0 ]; then
    SKIP_JSON+=","
  fi
  SKIP_JSON+="\"${SKIP_CANDIDATES[$i]}\""
done
SKIP_JSON+="]"

# Write final results
cat > "$RESULTS_FILE" <<ENDJSON
{
  "model": "$MODEL",
  "timestamp": "$TIMESTAMP",
  "baseline_f1": $BASELINE_F1,
  "min_f1_threshold": $MIN_F1,
  "phase_results": $RESULTS_JSON,
  "recommended_skip_phases": $SKIP_JSON,
  "recommended_profile_update": {
    "model": "$MODEL",
    "skip_phases": $SKIP_JSON,
    "notes": "Generated by harness-stress-test.sh on $TIMESTAMP"
  }
}
ENDJSON

echo ""
echo "=== Summary ==="
echo "Baseline F1:      $BASELINE_F1"
echo "Min F1 threshold: $MIN_F1"
echo "Phases tested:    ${#PHASES_TO_TEST[@]}"
echo "Skip candidates:  ${SKIP_CANDIDATES[*]:-none}"
echo ""
echo "Results saved to: $RESULTS_FILE"
echo ""
echo "To apply these recommendations, update model_capability.profiles in config/default-config.json:"
echo "  \"skip_phases\": $SKIP_JSON"
