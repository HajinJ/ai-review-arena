#!/usr/bin/env bash
# =============================================================================
# ai-review-arena: Findings Aggregator
#
# Usage: aggregate-findings.sh <session_dir> <config_file>
#
# Reads all findings_*.json files from session directory, merges,
# deduplicates (by file + line proximity), and outputs unified JSON array.
#
# Output: JSON array of aggregated findings, or "LGTM" if none found.
# =============================================================================

set -uo pipefail

# --- Arguments ---
SESSION_DIR="${1:?Usage: aggregate-findings.sh <session_dir> <config_file>}"
CONFIG_FILE="${2:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Dependencies ---
if ! command -v jq &>/dev/null; then
  echo "LGTM"
  exit 0
fi

# --- Stale review detection (Code Factory pattern) ---
# If code changed since review started, mark findings as potentially stale
STALE_REVIEW=false
REVIEW_HASH_FILE="${SESSION_DIR}/.review_commit_hash"
if [ -f "$REVIEW_HASH_FILE" ]; then
  REVIEW_HASH=$(cat "$REVIEW_HASH_FILE" || true)
  CURRENT_HASH=$(git rev-parse HEAD 2>/dev/null || true)
  if [ -n "$REVIEW_HASH" ] && [ -n "$CURRENT_HASH" ] && [ "$REVIEW_HASH" != "$CURRENT_HASH" ]; then
    STALE_REVIEW=true
    echo "[arena:warn] Review may be stale: code changed since review started (review: ${REVIEW_HASH:0:8}, current: ${CURRENT_HASH:0:8})" >&2
  fi
fi

# --- Read config ---
CONFIDENCE_THRESHOLD=40
LINE_PROXIMITY=3

if [ -n "$CONFIG_FILE" ] && [ -f "$CONFIG_FILE" ]; then
  cfg_threshold=$(jq -r '.review.confidence_threshold // empty' "$CONFIG_FILE" || true)
  if [ -n "$cfg_threshold" ]; then
    CONFIDENCE_THRESHOLD="$cfg_threshold"
  fi
fi

# --- Collect all findings files ---
FINDINGS_FILES=()
for f in "${SESSION_DIR}"/findings_*.json; do
  [ -f "$f" ] || continue
  # Validate JSON
  if jq . "$f" &>/dev/null 2>&1; then
    FINDINGS_FILES+=("$f")
  fi
done

if [ ${#FINDINGS_FILES[@]} -eq 0 ]; then
  echo "LGTM"
  exit 0
fi

# --- Merge all findings into a single array ---
# Each findings file has structure: {model, role, file, findings: [...], summary}
# We extract and flatten all findings, adding model/role/file metadata to each
MERGED_FINDINGS=$(
  for f in "${FINDINGS_FILES[@]}"; do
    jq -c '
      .model as $model |
      .role as $role |
      .file as $file |
      (.findings // [])[] |
      . + {model: $model, role: $role, file: $file, models: [$model]}
    ' "$f" 2>/dev/null || true
  done | jq -s '.'
)

if [ -z "$MERGED_FINDINGS" ] || [ "$MERGED_FINDINGS" = "[]" ] || [ "$MERGED_FINDINGS" = "null" ]; then
  echo "LGTM"
  exit 0
fi

# --- Normalize severity values from external CLIs ---
NORMALIZER="$SCRIPT_DIR/normalize-severity.sh"
if [ -f "$NORMALIZER" ] && [ -x "$NORMALIZER" ]; then
  NORMALIZED=$(echo "$MERGED_FINDINGS" | "$NORMALIZER" 2>/dev/null)
  if [ -n "$NORMALIZED" ]; then
    MERGED_FINDINGS="$NORMALIZED"
  fi
fi

# --- Check for errors (all entries have error field) ---
HAS_FINDINGS=$(echo "$MERGED_FINDINGS" | jq '[.[] | select(.title != null and .title != "")] | length' || echo "0")
if [ "$HAS_FINDINGS" -eq 0 ]; then
  echo "LGTM"
  exit 0
fi

# --- Deduplicate and aggregate ---
# Group by file + approximate line (within LINE_PROXIMITY lines) + similar title
# For duplicates: take highest severity, average confidence, collect all models
AGGREGATED=$(echo "$MERGED_FINDINGS" | jq --argjson proximity "$LINE_PROXIMITY" --argjson threshold "$CONFIDENCE_THRESHOLD" '
  # Severity ordering for comparison
  def severity_rank:
    if . == "critical" then 4
    elif . == "high" then 3
    elif . == "medium" then 2
    elif . == "low" then 1
    else 0 end;

  def rank_to_severity:
    if . >= 4 then "critical"
    elif . >= 3 then "high"
    elif . >= 2 then "medium"
    elif . >= 1 then "low"
    else "info" end;

  # Filter out entries without title (errors, empty)
  [.[] | select(.title != null and .title != "")] |

  # Group findings by file and line proximity
  group_by(.file) |
  map(
    # Within each file group, cluster by line proximity + similar title
    reduce .[] as $finding (
      [];
      . as $clusters |
      # Find matching cluster index (use $clusters to reference outer accumulator)
      (reduce range($clusters | length) as $i (
        null;
        if . != null then . else
          (if ($clusters[$i] | last | .file) == $finding.file and
              ((($clusters[$i] | last | .line // 0) - ($finding.line // 0)) | fabs) <= $proximity and
              (($clusters[$i] | last | .title | ascii_downcase | split(" ")) as $t1 |
               ($finding.title | ascii_downcase | split(" ")) as $t2 |
               ([$t1 | length, $t2 | length, 3] | min) as $n |
               ($t1[0:$n] | join(" ")) == ($t2[0:$n] | join(" ")))
          then $i else null end)
        end
      )) as $match_idx |
      if $match_idx != null then
        .[$match_idx] += [$finding]
      else
        . + [[$finding]]
      end
    )
  ) |
  flatten(1) |

  # Process each cluster into a single finding
  map(
    if length == 1 then
      .[0] |
      {
        file,
        line: (.line // 0),
        title,
        description: (.description // ""),
        suggestion: (.suggestion // ""),
        severity: (.severity // "medium"),
        confidence: (.confidence // 50),
        models: (.models // [.model]),
        role: (.role // "unknown"),
        cross_model_agreement: false
      }
    else
      # Multiple findings in cluster - aggregate
      {
        file: .[0].file,
        line: ([.[].line // 0] | min),
        title: .[0].title,
        description: (
          [.[].description | select(. != null and . != "")] |
          if length > 0 then .[0] else "" end
        ),
        suggestion: (
          [.[].suggestion | select(. != null and . != "")] |
          if length > 0 then .[0] else "" end
        ),
        severity: (
          [.[].severity | severity_rank] | max | rank_to_severity
        ),
        confidence: (
          [.[].confidence // 50] | add / length | floor |
          # Boost confidence by 15% for cross-model agreement, cap at 100
          . + 15 | if . > 100 then 100 else . end
        ),
        models: ([.[].model] | unique),
        role: .[0].role,
        cross_model_agreement: (
          [.[].model] | unique | length > 1
        )
      }
    end
  ) |

  # Filter by severity-aware confidence threshold
  map(select(
    (.severity == "critical" and .confidence >= ($threshold - 30)) or
    (.severity == "high" and .confidence >= ($threshold - 15)) or
    (.severity == "medium" and .confidence >= $threshold) or
    (.severity == "low" and .confidence >= ($threshold + 10)) or
    (.confidence >= $threshold)
  )) |

  # Sort by confidence descending, then severity
  sort_by(-(
    (.confidence * 10) +
    (if .severity == "critical" then 400
     elif .severity == "high" then 300
     elif .severity == "medium" then 200
     elif .severity == "low" then 100
     else 0 end)
  ))
')

if [ -z "$AGGREGATED" ] || [ "$AGGREGATED" = "[]" ] || [ "$AGGREGATED" = "null" ]; then
  echo "LGTM"
  exit 0
fi

# --- Mark stale findings ---
if [ "$STALE_REVIEW" = "true" ]; then
  AGGREGATED=$(echo "$AGGREGATED" | jq 'map(. + {stale: true, stale_warning: "Code changed after review — re-verify before acting on this finding"})')
fi

echo "$AGGREGATED"
