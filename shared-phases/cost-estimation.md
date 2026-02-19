# Shared Phase: Cost & Time Estimation

Based on the decided intensity, estimate costs and time before proceeding. This phase runs immediately after intensity decision for ALL intensity levels.

**Purpose**: Give the user visibility into expected resource usage before committing to execution.

## Variables (set by calling pipeline)

- `PIPELINE_TYPE`: "code" or "business"
- `INTENSITY`: Decided intensity level
- `TOTAL_INPUT_LINES`: Estimated input size (for code pipeline)

## Estimation Method

Use the cost-estimator.sh script for consistent estimation across all pipelines:

```bash
bash "${SCRIPTS_DIR}/cost-estimator.sh" "${CONFIG_FILE}" \
  --intensity "${INTENSITY}" \
  --pipeline "${PIPELINE_TYPE}" \
  --lines "${TOTAL_INPUT_LINES}" \
  ${HAS_FIGMA:+--figma}
```

For JSON output (programmatic use):
```bash
bash "${SCRIPTS_DIR}/cost-estimator.sh" "${CONFIG_FILE}" \
  --intensity "${INTENSITY}" \
  --pipeline "${PIPELINE_TYPE}" \
  --lines "${TOTAL_INPUT_LINES}" \
  --json
```

## Display to User

The script outputs a formatted summary including:
- Intensity and pipeline type
- Claude agent count and external CLI count
- Per-phase token and cost breakdown
- Total estimated tokens, cost, and time

## Decision

- IF `--non-interactive` OR cost <= `config.cost_estimation.auto_proceed_under_dollars`: Proceed automatically
- IF user selects "Cancel": Stop pipeline, display summary of what was gathered so far
- IF user selects "Adjust intensity": Prompt for new intensity level, re-run with `--intensity` override
- IF user selects "Proceed": Continue to next phase

## Session Cleanup Note

At the end of the pipeline (Phase 7 / B7), clean up session directories:
```bash
bash "${SCRIPTS_DIR}/cache-manager.sh" cleanup-sessions --max-age 24
```
