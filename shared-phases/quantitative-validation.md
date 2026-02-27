# Shared Phase: Quantitative Validation (Business Pipeline)

**Applies to**: deep, comprehensive intensity only. Skip for quick and standard.

**Purpose**: Cross-validate all numerical claims in business content. A 2-agent team verifies market sizes, growth rates, financial projections, and unit economics against external data sources.

## Variables (set by calling pipeline)

- `CONTENT_DRAFT`: Business content with numerical claims
- `EVIDENCE_SOURCES`: Sources cited in the content
- `MARKET_CONTEXT`: Market research results from Phase B1

## Steps

1. **Extract Numerical Claims**:
   Parse the content to identify all quantitative assertions:
   - Market size figures (TAM, SAM, SOM)
   - Growth rates and projections
   - Financial metrics (revenue, margins, unit economics)
   - Comparative statistics (X% better than, Y times faster)
   - Time-based claims (by 2025, within 12 months)

2. **Create Validation Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "quant-validation-{YYYYMMDD-HHMMSS}",
     description: "Quantitative claim validation"
   )
   ```

3. **Create Tasks**:
   ```
   TaskCreate(
     subject: "Verify numerical claims against external sources",
     description: "Cross-reference all numerical claims in the content against authoritative data sources. Use WebSearch extensively.",
     activeForm: "Verifying numerical claims"
   )

   TaskCreate(
     subject: "Validate projection methodology and assumptions",
     description: "Assess whether projections follow sound methodology, assumptions are reasonable, and math is internally consistent.",
     activeForm: "Validating projection methodology"
   )
   ```

4. **Spawn Validation Agents** (in parallel):

   ### data-verifier
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "quant-validation-{session}",
     name: "data-verifier",
     prompt: "You are a Data Verification Specialist. Cross-reference ALL numerical claims.

     CONTENT:
     {CONTENT_DRAFT}

     CITED SOURCES:
     {EVIDENCE_SOURCES}

     For EACH numerical claim:
     1. Use WebSearch to find the authoritative source
     2. Compare stated value vs actual value
     3. Calculate deviation percentage
     4. Rate: VERIFIED (within {tolerance_pct}%) | UNVERIFIED (no source found) | CONTRADICTED (deviation > {tolerance_pct}%)

     Send results as JSON to team lead:
     {
       claims: [
         {claim, stated_value, verified_value, source, status, deviation_pct}
       ],
       summary: {total, verified, unverified, contradicted}
     }"
   )
   ```

   ### methodology-auditor
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "quant-validation-{session}",
     name: "methodology-auditor",
     prompt: "You are a Financial Methodology Auditor. Validate all projections and calculations.

     CONTENT:
     {CONTENT_DRAFT}

     MARKET CONTEXT:
     {MARKET_CONTEXT}

     For EACH projection or calculation:
     1. Check if assumptions are stated
     2. Verify math consistency (do the numbers add up?)
     3. Compare growth assumptions against industry benchmarks
     4. Check for common projection errors:
        - Linear extrapolation of exponential trends
        - Ignoring market saturation
        - Unrealistic conversion rates
        - Missing seasonality adjustments

     Send results as JSON to team lead:
     {
       projections: [
         {projection, methodology, assumptions_stated, math_consistent, benchmark_comparison, rating}
       ],
       internal_consistency: {consistent: true/false, issues: []},
       summary: {total_projections, sound, questionable, flawed}
     }"
   )
   ```

5. **Collect and Merge Results**: Wait for both agents, combine into unified report.

6. **Shutdown Team** and cleanup.

7. **Display Results**:
   ```
   ## Quantitative Validation
   - Claims checked: {N}
   - Verified: {V} | Unverified: {U} | Contradicted: {C}
   - Projections audited: {P}
   - Sound: {S} | Questionable: {Q} | Flawed: {F}
   - Internal consistency: {pass/fail}
   ```

## Configuration

Settings from `config.quantitative_validation`:
- `enabled`: Whether quantitative validation is active (default: true)
- `min_intensity`: Minimum intensity to run (default: deep)
- `checks`: Types of checks to perform (default: [market_size, growth_rates, financial_projections, unit_economics])
- `tolerance_pct`: Acceptable deviation percentage (default: 20)

## Error Handling

- WebSearch unavailable: Mark claims as "unverified" rather than failing
- Cannot parse numbers: Skip unparseable claims, note in report
- Agent timeout: Proceed with available results
- All agents fail: Skip validation, warn: "Quantitative validation unavailable"
