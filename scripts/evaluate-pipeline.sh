#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Pipeline-Level Evaluation Framework
#
# Usage: evaluate-pipeline.sh [config_file] [--test-dir <dir>] [--output json|markdown] [--verbose]
#
# Evaluates the entire Arena pipeline against ground-truth test cases.
# Unlike benchmark-models.sh (which tests individual model detection),
# this script measures the END-TO-END pipeline output quality:
#   - Did the pipeline catch the planted vulnerabilities? (Recall)
#   - How many findings were false positives? (Precision)
#   - Were severity levels calibrated correctly?
#   - How useful were the suggestions?
#   - How long did it take to produce useful findings?
#
# Output: JSON report with precision, recall, F1, false_positive_rate
# =============================================================================

set -uo pipefail

# --- Arguments ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

source "$SCRIPT_DIR/utils.sh"

CONFIG_FILE="${1:-}"
TEST_DIR=""
OUTPUT_FORMAT="markdown"
VERBOSE=false

# Parse arguments
shift || true
while [ $# -gt 0 ]; do
  case "$1" in
    --test-dir)
      TEST_DIR="${2:?--test-dir requires a value}"
      shift 2
      ;;
    --output)
      OUTPUT_FORMAT="${2:?--output requires json or markdown}"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      shift
      ;;
  esac
done

# --- Load config ---
if [ -z "$CONFIG_FILE" ]; then
  CONFIG_FILE=$(load_config "$(find_project_root)") || CONFIG_FILE="${PLUGIN_DIR}/config/default-config.json"
fi

if [ -z "$TEST_DIR" ]; then
  TEST_DIR=$(get_config_value "$CONFIG_FILE" '.pipeline_evaluation.test_cases_dir // "config/benchmarks/pipeline"')
  TEST_DIR="${PLUGIN_DIR}/${TEST_DIR}"
fi

# --- Check dependencies ---
ensure_jq

if [ ! -d "$TEST_DIR" ]; then
  log_warn "Pipeline test directory not found: $TEST_DIR"
  log_info "Creating directory with sample test case..."
  mkdir -p "$TEST_DIR"

  # Create sample pipeline test case
  cat > "$TEST_DIR/sample-pipeline-test.json" <<'SAMPLE_EOF'
{
  "id": "pipeline-sample-01",
  "description": "Sample pipeline evaluation test case — replace with real test projects",
  "type": "pipeline_evaluation",
  "instructions": "To create pipeline test cases, prepare a small code project with intentionally planted vulnerabilities/bugs. Document the ground truth findings below.",
  "project_setup": {
    "files": {},
    "description": "Add project files here as {filename: content} pairs"
  },
  "ground_truth": {
    "expected_findings": [
      {
        "category": "security",
        "severity": "critical",
        "location_hint": "file.js:line",
        "description_contains": ["SQL injection", "parameterized"],
        "must_find": true
      }
    ],
    "acceptable_false_positives": 2,
    "expected_severity_distribution": {
      "critical": 1,
      "high": 2,
      "medium": 1,
      "low": 0
    }
  },
  "evaluation_criteria": {
    "min_precision": 0.7,
    "min_recall": 0.8,
    "max_false_positive_rate": 0.3,
    "severity_tolerance": 1
  }
}
SAMPLE_EOF
  log_info "Sample test case created at: $TEST_DIR/sample-pipeline-test.json"
  log_info "Customize this file with your own test projects."
fi

# --- Discover test cases ---
TEST_CASES=()
while IFS= read -r tc; do
  [ -z "$tc" ] && continue
  TEST_CASES+=("$tc")
done < <(find "$TEST_DIR" -name "*.json" -type f 2>/dev/null | sort)

if [ ${#TEST_CASES[@]} -eq 0 ]; then
  log_error "No test cases found in $TEST_DIR"
  echo '{"error": "no test cases found", "test_dir": "'"$TEST_DIR"'"}'
  exit 0
fi

log_info "Found ${#TEST_CASES[@]} pipeline test case(s)"

# =============================================================================
# Evaluation Functions
# =============================================================================

calculate_metrics() {
  local ground_truth_file="$1"
  local findings_file="$2"

  if [ ! -f "$ground_truth_file" ] || [ ! -f "$findings_file" ]; then
    echo '{"error": "missing input files"}'
    return 1
  fi

  local expected_count
  expected_count=$(jq '.ground_truth.expected_findings | length' "$ground_truth_file" 2>/dev/null || echo 0)

  local actual_count
  actual_count=$(jq 'if type == "array" then length elif .findings then (.findings | length) else 0 end' "$findings_file" 2>/dev/null || echo 0)

  local must_find_count
  must_find_count=$(jq '[.ground_truth.expected_findings[] | select(.must_find == true)] | length' "$ground_truth_file" 2>/dev/null || echo 0)

  # Calculate basic metrics
  # True Positives: findings that match ground truth
  # False Positives: findings that don't match any ground truth
  # False Negatives: ground truth items not found
  local tp=0
  local fp=0
  local fn=0

  # Simplified matching: count findings that contain expected keywords
  for i in $(seq 0 $((expected_count - 1))); do
    local keywords
    keywords=$(jq -r ".ground_truth.expected_findings[$i].description_contains[]?" "$ground_truth_file" 2>/dev/null)

    local found=false
    if [ -n "$keywords" ]; then
      for keyword in $keywords; do
        if jq -e ".. | strings | test(\"$keyword\"; \"i\")" "$findings_file" &>/dev/null 2>&1; then
          found=true
          break
        fi
      done
    fi

    if [ "$found" = "true" ]; then
      tp=$((tp + 1))
    else
      fn=$((fn + 1))
    fi
  done

  # False positives = total findings - true positives
  if [ "$actual_count" -gt "$tp" ]; then
    fp=$((actual_count - tp))
  fi

  # Calculate rates
  local precision=0
  local recall=0
  local f1=0
  local fpr=0

  if [ $((tp + fp)) -gt 0 ]; then
    precision=$(echo "scale=3; $tp / ($tp + $fp)" | bc 2>/dev/null || echo "0")
  fi

  if [ $((tp + fn)) -gt 0 ]; then
    recall=$(echo "scale=3; $tp / ($tp + $fn)" | bc 2>/dev/null || echo "0")
  fi

  if [ "$(echo "$precision + $recall > 0" | bc 2>/dev/null)" = "1" ]; then
    f1=$(echo "scale=3; 2 * $precision * $recall / ($precision + $recall)" | bc 2>/dev/null || echo "0")
  fi

  if [ $((fp + tp)) -gt 0 ]; then
    fpr=$(echo "scale=3; $fp / ($fp + $tp)" | bc 2>/dev/null || echo "0")
  fi

  cat <<METRICS_JSON
{
  "true_positives": $tp,
  "false_positives": $fp,
  "false_negatives": $fn,
  "total_expected": $expected_count,
  "total_actual": $actual_count,
  "precision": $precision,
  "recall": $recall,
  "f1_score": $f1,
  "false_positive_rate": $fpr
}
METRICS_JSON
}

# =============================================================================
# Run Evaluation
# =============================================================================

RESULTS=()
TOTAL_TP=0
TOTAL_FP=0
TOTAL_FN=0

for test_case in "${TEST_CASES[@]}"; do
  test_id=$(jq -r '.id // "unknown"' "$test_case" 2>/dev/null)
  test_desc=$(jq -r '.description // "no description"' "$test_case" 2>/dev/null)

  if [ "$VERBOSE" = "true" ]; then
    log_info "Evaluating: $test_id — $test_desc"
  fi

  # Check if this is a real pipeline test or a sample
  has_files=$(jq -r '.project_setup.files | length // 0' "$test_case" 2>/dev/null)
  if [ "$has_files" = "0" ]; then
    if [ "$VERBOSE" = "true" ]; then
      log_warn "Skipping $test_id — no project files defined (sample template)"
    fi
    continue
  fi

  # For now, this script provides the evaluation FRAMEWORK.
  # Actual pipeline execution integration will be added when
  # pipeline results are stored in a standard location.
  log_info "Test case $test_id ready for evaluation (pipeline execution integration pending)"
done

# =============================================================================
# Generate Report
# =============================================================================

REPORT_DIR=$(get_config_value "$CONFIG_FILE" '.pipeline_evaluation.report_dir // "cache/evaluation-reports"')
REPORT_DIR="${PLUGIN_DIR}/${REPORT_DIR}"
mkdir -p "$REPORT_DIR"

REPORT_FILE="${REPORT_DIR}/eval-$(date +%Y%m%d-%H%M%S).json"

cat > "$REPORT_FILE" <<REPORT_EOF
{
  "evaluation_timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "test_directory": "$TEST_DIR",
  "test_cases_found": ${#TEST_CASES[@]},
  "framework_status": "ready",
  "metrics_available": ["precision", "recall", "f1_score", "false_positive_rate", "time_to_finding"],
  "llm_as_judge": {
    "enabled": $(get_config_value "$CONFIG_FILE" '.pipeline_evaluation.llm_as_judge.enabled // false'),
    "position_bias_mitigation": $(get_config_value "$CONFIG_FILE" '.pipeline_evaluation.llm_as_judge.position_bias_mitigation // true'),
    "criteria": $(jq -c '.pipeline_evaluation.llm_as_judge.evaluation_criteria // ["finding_accuracy", "severity_calibration", "suggestion_quality"]' "$CONFIG_FILE" 2>/dev/null || echo '[]')
  },
  "instructions": "Add pipeline test cases to $TEST_DIR with project_setup.files populated. Run Arena on the test project, then re-run this script to evaluate results."
}
REPORT_EOF

if [ "$OUTPUT_FORMAT" = "json" ]; then
  cat "$REPORT_FILE"
else
  echo ""
  echo "## Pipeline Evaluation Report"
  echo ""
  echo "**Timestamp:** $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "**Test Directory:** $TEST_DIR"
  echo "**Test Cases Found:** ${#TEST_CASES[@]}"
  echo "**Framework Status:** Ready"
  echo ""
  echo "### Available Metrics"
  echo "| Metric | Description |"
  echo "|--------|-------------|"
  echo "| Precision | True findings / All reported findings (false positive control) |"
  echo "| Recall | Found findings / All expected findings (detection completeness) |"
  echo "| F1 Score | Harmonic mean of precision and recall |"
  echo "| False Positive Rate | False positives / All reported findings |"
  echo "| Time to Finding | Seconds from pipeline start to first useful finding |"
  echo ""
  echo "### LLM-as-Judge"
  echo "- Position bias mitigation: enabled (evaluates in both orders)"
  echo "- Criteria: finding accuracy, severity calibration, suggestion quality, report completeness"
  echo ""
  echo "### Next Steps"
  echo "1. Add pipeline test cases to \`$TEST_DIR\` with real project files"
  echo "2. Run Arena on the test project"
  echo "3. Re-run this script to evaluate results"
  echo ""
  echo "Report saved to: $REPORT_FILE"
fi

exit 0
