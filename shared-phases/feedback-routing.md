# Shared Phase: Feedback-Based Routing

When `feedback.use_for_routing` is true in config, use accumulated feedback data to optimize model-category role assignments before spawning review agents.

## When to Apply

- During Phase 6 (Code Review) or Phase B6 (Business Review), before spawning reviewer teammates
- Only when `routing.strategy` is `"feedback_benchmark"` in config
- Falls back to default roles if insufficient feedback data

## Steps

1. **Check Feedback Availability**:
   ```bash
   bash "${SCRIPTS_DIR}/feedback-tracker.sh" recommend \
     --days $(jq -r '.feedback.report_period_days // 30' "$CONFIG_FILE") \
     --min-samples $(jq -r '.feedback.min_samples_for_routing // 5' "$CONFIG_FILE")
   ```

2. **Parse Recommendations**:
   The `recommend` command returns JSON with:
   - `recommendations`: Per-category best model rankings with combined scores
   - `routing_config`: Simple `{category: model}` mapping for direct use
   - `status`: "insufficient_data" if not enough feedback samples

3. **Apply to Role Assignments**:
   - If recommendations available: assign primary reviewer role for each category to the recommended model
   - If insufficient data: fall back to benchmark scores (`routing.strategy: "benchmark"`)
   - If no benchmarks either: fall back to default config roles (`routing.fallback: "default"`)

4. **Display Routing Decision** (if `output.show_model_attribution` is true):
   ```
   ## Review Routing (Feedback-Based)
   - security: {model} (combined score: {score}, source: {feedback+benchmark|feedback_only|benchmark_only})
   - bugs: {model} (combined score: {score}, source: ...)
   - architecture: {model} (combined score: {score}, source: ...)
   ...
   ```

## Scoring Formula

Combined score = (`feedback_weight` x feedback_accuracy) + (`benchmark_weight` x benchmark_F1)

Default weights from config:
- `routing.feedback_weight`: 0.6 (60% feedback)
- `routing.benchmark_weight`: 0.4 (40% benchmark)

Feedback is weighted higher because it reflects actual production usefulness, while benchmarks measure capability on synthetic test cases.
