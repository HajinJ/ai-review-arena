# Context Forwarding Interface

When a request spans multiple routes (multi-route), each pipeline produces a context output that is forwarded to the next pipeline.

## Context Outputs by Route

| Source Route | Context Output | Available Fields |
|-------------|---------------|-----------------|
| G (Business Content) | `business_content_output` | content_text, quality_scorecard, key_themes, audience, tone |
| H (Business Strategy) | `strategy_output` | analysis_summary, recommendations, market_data, competitive_landscape |
| I (Communication) | `communication_output` | draft_text, tone_analysis, audience_fit_score |
| A (Feature Impl) | `implementation_output` | files_changed, test_results, architecture_decisions |
| D (Code Review) | `review_output` | findings_summary, severity_counts, quality_score |

## Forwarding Rules

1. Context is passed as an additional `PRIOR_ROUTE_CONTEXT` variable
2. The receiving pipeline reads it in Phase 0/B0 alongside other context
3. Context is INFORMATIONAL — the receiving pipeline decides how to use it
4. Tiered token limits by field type:

| Field Type | Limit | Examples |
|-----------|-------|---------|
| summary_fields | 2,000 tokens | quality_scorecard, key_themes, severity_counts |
| content_text | 15,000 tokens | Full document if needed by next route |
| metadata | 1,000 tokens | audience, tone, audience_fit_score |
| **Total hard limit** | **20,000 tokens** | |

Overflow behavior:
- IF any field exceeds its limit: auto-summarize before forwarding
- IF total exceeds hard limit: drop content_text, keep summaries only

## Execution Order

1. Parse all intents from user request
2. Order by dependency: business routes before code routes
3. Execute sequentially
4. After each route completes, extract context output
5. Pass to next route as `PRIOR_ROUTE_CONTEXT`

## Example

```
Request: "Write a pitch deck and build a landing page based on it"

Sub-task 1: Route G (Business Content)
  Input: "Write a pitch deck"
  Output: business_content_output = {
    content_text: "<full pitch deck>",
    quality_scorecard: {accuracy: 88, audience_fit: 92, ...},
    key_themes: ["AI-powered trade compliance", "reduce costs by 60%"],
    audience: "investor",
    tone: "persuasive"
  }

Sub-task 2: Route A (Feature Implementation)
  Input: "Build a landing page"
  PRIOR_ROUTE_CONTEXT: business_content_output from Sub-task 1
  → Codebase analysis uses key_themes for content
  → Implementation uses tone and audience for design decisions
```
