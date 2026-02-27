# Example Pipeline Outputs

Sample outputs from the AI Review Arena pipeline at different intensity levels.

---

## Quick Intensity: Code Explanation

**Request:** "What does the `orchestrate-review.sh` script do?"

```
## Codebase Analysis (Phase 0.5)

Scanned project: ai-review-arena
- Language: Bash (78%), Python (12%), Markdown (10%)
- Convention: POSIX-compatible with bash extensions
- Logging: log_info/log_warn/log_error to stderr

## Answer

`orchestrate-review.sh` is the review orchestration script. It:

1. Accepts review parameters via stdin JSON (files, intensity, focus areas)
2. Records the current HEAD commit hash for stale review detection
3. Launches parallel review processes across enabled models (Claude agents, Codex CLI, Gemini CLI)
4. Waits for all reviewers to complete (with configurable timeouts)
5. Passes findings to `aggregate-findings.sh` for deduplication and merging
6. Compares current HEAD against the recorded hash — if code changed mid-review,
   all findings are marked `stale: true`
7. Returns aggregated findings as JSON to stdout

Cost: ~$0.02 (Claude solo, no debate)
```

---

## Standard Intensity: Code Review

**Request:** "Review this authentication middleware"

```
## Intensity Decision

intensity-advocate:   "Auth middleware is security-critical. Deep needed."
efficiency-advocate:  "Single file, well-scoped. Standard is sufficient."
risk-assessor:        "Authentication — medium-high risk. Standard minimum."
intensity-arbitrator: "Standard. Single file limits blast radius."

## Cost Estimate (Phase 0.2)

| Phase        | Estimated Cost |
|-------------|---------------|
| Codebase    | $0.03         |
| Stack       | $0.02         |
| Strategy    | $0.45         |
| Review (6 agents + 2 CLIs) | $1.20 |
| Debate (3 rounds) | $0.85  |
| Auto-fix    | $0.05         |
| Report      | $0.02         |
| **Total**   | **$2.62**     |

Proceeding (under $5.00 threshold).

## Review Findings (Phase 6)

### Round 1: Independent Review

| # | Severity | Category | Finding | Model | Confidence |
|---|----------|----------|---------|-------|-----------|
| 1 | high | security | JWT secret loaded from env without fallback — undefined secret disables auth silently | Claude (security-reviewer) | 85 |
| 2 | medium | bugs | Token expiry check uses `<` instead of `<=` — tokens valid for 1 extra second | Codex | 72 |
| 3 | low | performance | Synchronous `fs.readFileSync` for public key on every request | Gemini | 68 |
| 4 | medium | security | Missing rate limiting on auth endpoint | Claude (security-reviewer) | 78 |

### Round 2: Cross-Examination

Finding #1 (JWT secret):
  - Codex: AGREE (+10) "Confirmed — no default or error throw when JWT_SECRET is missing"
  - Gemini: AGREE (+5) "Silent auth bypass is critical, should be high severity"

Finding #2 (Token expiry):
  - Claude: PARTIAL (0) "Off-by-one exists but impact is 1 second, severity should be low"
  - Gemini: AGREE (+5) "Confirmed in jsonwebtoken source"

Finding #3 (Sync file read):
  - Claude: DISAGREE (-15) "Public key is cached after first read — see line 12"
  - Codex: DISAGREE (-10) "Caching layer exists, this is a false positive"

Finding #4 (Rate limiting):
  - Codex: PARTIAL (-5) "Rate limiting exists at nginx layer (infra config)"
  - Gemini: AGREE (+5) "Application-level rate limiting still recommended"

### Round 3: Defense

Finding #3: Gemini CONCEDES "Missed the caching on line 12. Withdrawing."

### Consensus

| # | Finding | Final Confidence | Verdict |
|---|---------|-----------------|---------|
| 1 | JWT secret silent bypass | 95 | CONFIRMED (unanimous) |
| 2 | Token expiry off-by-one | 67 | CONFIRMED (majority, downgraded to low) |
| 3 | Sync file read | -- | WITHDRAWN (conceded) |
| 4 | Missing app-level rate limit | 73 | CONFIRMED (majority) |

## Auto-Fix (Phase 6.5)

No findings eligible for auto-fix (all security-related or above threshold).

## Final Report

Quality Score: 82/100
Findings: 3 confirmed, 1 withdrawn
Models: Claude (lead), Codex (cross-exam), Gemini (cross-exam)
Fallback Level: 0 (full operation)
Cost: $2.48 actual
```

---

## Deep Intensity: Feature Implementation

**Request:** "Implement OAuth2 login with Google provider"

```
## Intensity Decision

intensity-advocate:   "OAuth involves token handling, redirect flows, session
                       management. Comprehensive needed for security coverage."
efficiency-advocate:  "Google OAuth is well-documented. Deep is sufficient."
risk-assessor:        "Authentication system. Security-critical. Deep minimum."
intensity-arbitrator: "Deep. Security-critical but follows standard OAuth2 flow."

## Cost Estimate (Phase 0.2)

| Phase        | Estimated Cost |
|-------------|---------------|
| Codebase    | $0.03         |
| Stack       | $0.02         |
| Research    | $0.65         |
| Compliance  | $0.35         |
| Strategy    | $0.55         |
| Implementation + Review (10 agents + 3 CLIs) | $2.80 |
| Debate (3 rounds) | $1.10  |
| Auto-fix    | $0.08         |
| Report      | $0.03         |
| **Total**   | **$5.61**     |

Proceed? [Yes] [Adjust intensity] [Cancel]
> Yes

## Pre-Implementation Research (Phase 2)

Research direction debate:
- "Focus on PKCE flow for public clients" (selected)
- "Survey state parameter CSRF protection" (selected)
- "Review Google OAuth2 deprecation timeline" (selected)

Key findings:
- Google requires PKCE for new apps as of 2025
- State parameter is mandatory for CSRF prevention
- Refresh token rotation recommended

## Compliance Check (Phase 3)

Detected: "login" + "OAuth" → OWASP Authentication Guidelines
Applicable rules:
- A07:2021 — Identification and Authentication Failures
- Session fixation prevention required
- Secure cookie attributes (HttpOnly, Secure, SameSite)

## Intensity Checkpoint (Phase 2.9)

Research confirmed standard OAuth2 complexity. Maintaining deep intensity.

## Implementation Strategy (Phase 5.5)

Success Criteria:
1. Google OAuth2 redirect returns 302 to Google consent page
   → verify: curl -I /auth/google
2. Callback exchanges code for tokens successfully
   → verify: mock OAuth flow with test tokens
3. Invalid state parameter returns 403
   → verify: curl with tampered state
4. Session created with secure cookie attributes
   → verify: inspect Set-Cookie header
5. Refresh token stored encrypted at rest
   → verify: check database for plaintext tokens

## Review Findings (Phase 6)

10 agents + Codex + Gemini reviewed implementation.
Findings: 2 high, 3 medium, 1 low (after 3-round debate).

## Final Report

Quality Score: 88/100
Success Criteria: 5/5 PASS
Scope Verdict: CLEAN
Findings: 6 confirmed, 2 withdrawn
Cost: $5.23 actual
```

---

## Business Review: Content Review (Standard)

**Request:** "Review this investor pitch deck for TradeFlow AI"

```
## Intensity Decision

intensity-advocate:   "Investor-facing content. Accuracy and credibility are critical."
efficiency-advocate:  "Pitch deck is focused scope. Standard is sufficient."
risk-assessor:        "External exposure to investors. Brand/trust risk is high."
intensity-arbitrator: "Standard. Important but focused scope."

## Business Context (Phase B0.5)

Extracted from docs/:
- Product: AI-powered trade compliance automation
- Value prop: 60% cost reduction, 99.2% accuracy
- Target: Mid-market importers (500-5000 SKUs)
- Stage: Pre-seed

## Review Findings (Phase B6)

### Round 1: 5-Agent Review + External CLIs

| # | Severity | Category | Finding | Agent | Confidence |
|---|----------|----------|---------|-------|-----------|
| 1 | high | accuracy | TAM claim "$47B customs market" — source cited is 2019, current estimates are $52B | accuracy-evidence-reviewer | 82 |
| 2 | medium | audience | Slide 3 uses technical jargon ("HS code classification") without explanation — investors may not know customs terminology | audience-fit-reviewer | 75 |
| 3 | medium | positioning | "Only AI solution for customs" — competitor TradeLens (IBM/Maersk) exists | competitive-positioning-reviewer | 88 |
| 4 | low | narrative | Slides 7-9 break narrative flow — financials before product demo | communication-narrative-reviewer | 65 |
| 5 | medium | accuracy | "99.2% accuracy" claim has no methodology or benchmark cited | Codex (cross-reviewer) | 78 |

### Round 2: Cross-Examination

Finding #3 (positioning):
  - Codex: AGREE (+10) "TradeLens shutdown announced Jan 2023, but Descartes CustomsInfo is active competitor"
  - Gemini: PARTIAL (+5) "Claim is misleading even without TradeLens — recommend 'leading' instead of 'only'"

### Round 3: Defense

All findings defended. Finding #3 modified: "Only" changed to "leading" per reviewer consensus.

### Consensus

| # | Finding | Final Confidence | Action |
|---|---------|-----------------|--------|
| 1 | Outdated TAM figure | 87 | Update to $52B with 2024 source |
| 2 | Technical jargon | 70 | Add glossary slide or inline definitions |
| 3 | Overclaimed positioning | 93 | Change "only" to "leading" |
| 4 | Narrative flow | 60 | Reorder slides (suggestion only) |
| 5 | Uncited accuracy claim | 83 | Add methodology footnote |

## Auto-Revise (Phase B6.5)

Applied: Finding #1 (TAM update), #3 (positioning language), #5 (added footnote placeholder)
Manual review needed: #2 (glossary), #4 (slide reorder)

## Quality Scorecard

| Dimension | Score |
|-----------|-------|
| Factual Accuracy | 72/100 |
| Audience Fit | 78/100 |
| Competitive Positioning | 65/100 |
| Narrative Quality | 80/100 |
| Overall | 74/100 |

Cost: $1.85 actual
```
