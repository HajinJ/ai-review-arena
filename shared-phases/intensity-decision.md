# Shared Phase: Intensity Decision (Agent Teams Debate)

**MANDATORY for all requests.** Determine the appropriate intensity level through adversarial debate among Claude agents. Skip only if user explicitly specified `--intensity`.

**Purpose**: Prevent both under-engineering and over-engineering. No single Claude instance can reliably judge complexity alone.

## Variables (set by calling pipeline before including this phase)

- `PIPELINE_TYPE`: "code" or "business"
- `USER_REQUEST`: The original user request
- `DISCOVERED_CONTEXT`: Context gathered in Phase 0/B0
- `PROJECT_CONTEXT`: Detected project type, stack, etc.
- `TEAM_PREFIX`: Team name prefix ("intensity-decision" for code, "biz-intensity-decision" for business)

## Steps

1. **Create Decision Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "{TEAM_PREFIX}-{YYYYMMDD-HHMMSS}",
     description: "{PIPELINE_TYPE} intensity level determination debate"
   )
   ```

2. **Create Debate Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for higher {PIPELINE_TYPE} intensity",
     description: "Argue for the highest reasonable intensity level. Provide specific technical/business reasoning.",
     activeForm: "Advocating for higher intensity"
   )

   TaskCreate(
     subject: "Advocate for lower {PIPELINE_TYPE} intensity",
     description: "Argue for the lowest reasonable intensity level. Consider practicality and cost. Provide specific reasoning.",
     activeForm: "Advocating for lower intensity"
   )

   TaskCreate(
     subject: "Assess {PIPELINE_TYPE} risk and impact",
     description: "Evaluate risk dimensions relevant to this request. Provide risk assessment with severity rating.",
     activeForm: "Assessing risk and impact"
   )

   TaskCreate(
     subject: "Arbitrate {PIPELINE_TYPE} intensity decision",
     description: "Wait for all three advocates. Weigh merits and decide final intensity (quick/standard/deep/comprehensive). Send decision to team lead.",
     activeForm: "Arbitrating intensity decision"
   )
   ```

3. **Spawn Debate Agents** (all in parallel):

   ### intensity-advocate

   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "{TEAM_PREFIX}-{session}",
     name: "intensity-advocate",
     prompt: "You are the Intensity Advocate. Argue for the HIGHEST reasonable intensity level.

     USER REQUEST: {USER_REQUEST}
     CONTEXT: {DISCOVERED_CONTEXT}
     PROJECT: {PROJECT_CONTEXT}
     PIPELINE: {PIPELINE_TYPE}

     ## Code Pipeline Considerations:
     - Hidden complexity (deadlock bugs seem simple but are concurrency issues)
     - Security implications (auth/payment touches are high-risk)
     - Production impact (production bugs need more scrutiny)
     - Cross-module effects (changes that ripple through the system)
     - Compliance requirements (features touching user data)

     ## Business Pipeline Considerations:
     - Audience Exposure (internal=low, investor/media=high, regulatory=critical)
     - Strategic Impact (minor edit=low, business plan=critical)
     - Accuracy Sensitivity (qualitative claims=low, financial projections=high)
     - Brand Risk (internal=low, public-facing=high)
     - Cross-Document Impact (sets precedents for other docs?)

     Present your argument to intensity-arbitrator via SendMessage.
     Engage with efficiency-advocate's counter-arguments.
     Continue until intensity-arbitrator makes a decision."
   )
   ```

   ### efficiency-advocate

   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "{TEAM_PREFIX}-{session}",
     name: "efficiency-advocate",
     prompt: "You are the Efficiency Advocate. Argue for the LOWEST reasonable intensity level.

     USER REQUEST: {USER_REQUEST}
     CONTEXT: {DISCOVERED_CONTEXT}
     PROJECT: {PROJECT_CONTEXT}
     PIPELINE: {PIPELINE_TYPE}

     ## Code Pipeline Considerations:
     - Is the scope truly limited? (single file, single function)
     - Are existing patterns reusable? (well-known solutions)
     - Is the risk actually low? (non-critical path, internal tool)
     - Would higher intensity waste resources without proportional benefit?

     ## Business Pipeline Considerations:
     - Is this internal-only? (drafts rarely need multi-agent review)
     - Are there existing templates? (template-based = lower risk)
     - Is it time-sensitive? (speed > exhaustive review)
     - Is this a minor revision to already-reviewed content?
     - Will the content go through additional human review?

     Present your argument to intensity-arbitrator via SendMessage.
     Engage with intensity-advocate's counter-arguments.
     Continue until intensity-arbitrator makes a decision."
   )
   ```

   ### risk-assessor

   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "{TEAM_PREFIX}-{session}",
     name: "risk-assessor",
     prompt: "You are the Risk Assessor. Provide an objective risk evaluation.

     USER REQUEST: {USER_REQUEST}
     CONTEXT: {DISCOVERED_CONTEXT}
     PROJECT: {PROJECT_CONTEXT}
     PIPELINE: {PIPELINE_TYPE}

     ## Code Risk Dimensions:
     1. Production Risk: Is this production code? What if the change has a bug?
     2. Security Risk: Does this touch auth, data handling, or network?
     3. Complexity Risk: Concurrency, distributed systems, or state management?
     4. Data Risk: Could this cause data loss, corruption, or leaks?
     5. Blast Radius: How many users/systems affected if something goes wrong?

     ## Business Risk Dimensions:
     1. Audience Exposure: Internal draft(LOW) → Customer(MED) → Investor(HIGH) → Regulatory(CRITICAL)
     2. Strategic Impact: Minor edit(LOW) → Individual doc(MED) → Core positioning(HIGH) → Full plan(CRITICAL)
     3. Accuracy Sensitivity: Qualitative(LOW) → Specific features(MED) → Numbers(HIGH) → Regulatory(CRITICAL)
     4. Brand Risk: Internal(LOW) → Customer(MED) → Public-facing(HIGH) → PR/Media(CRITICAL)

     Rate overall risk as: LOW / MEDIUM / HIGH / CRITICAL
     Send your assessment to intensity-arbitrator via SendMessage."
   )
   ```

   ### intensity-arbitrator

   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "{TEAM_PREFIX}-{session}",
     name: "intensity-arbitrator",
     prompt: "You are the Intensity Arbitrator. Make the FINAL intensity decision.

     Wait for arguments from:
     1. intensity-advocate (argues higher)
     2. efficiency-advocate (argues lower)
     3. risk-assessor (risk evaluation)

     After receiving all arguments:
     1. Weigh technical/business merits
     2. Consider the risk assessment
     3. Decide: quick, standard, deep, or comprehensive
     4. Provide clear justification

     ## Code Intensity Guidelines:
     - quick: Single element, obvious change, no risk
     - standard: Multi-file, moderate complexity, low-medium risk
     - deep: Complex logic, security-sensitive, high risk, compliance needed
     - comprehensive: System-wide, critical security (auth/payment), needs model benchmarking

     ## Business Intensity Guidelines:
     - quick: Internal notes, minor text edits, simple email drafts
     - standard: Individual documents, standard proposals, blog posts
     - deep: Strategic documents, investor decks, public-facing content
     - comprehensive: Full business plans, regulatory filings, fundraising materials

     Send your final decision to the team lead via SendMessage:
     INTENSITY_DECISION: {level}
     JUSTIFICATION: {reasoning}
     RISK_LEVEL: {from risk-assessor}
     KEY_FACTORS: {bullet points}"
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{advocate_task}", owner: "intensity-advocate")
   TaskUpdate(taskId: "{efficiency_task}", owner: "efficiency-advocate")
   TaskUpdate(taskId: "{risk_task}", owner: "risk-assessor")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "intensity-arbitrator")
   ```

5. **Wait for Decision**: Wait for intensity-arbitrator to send the final decision via SendMessage.

6. **Shutdown Decision Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "intensity-advocate", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "efficiency-advocate", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "risk-assessor", content: "Decision made.")
   SendMessage(type: "shutdown_request", recipient: "intensity-arbitrator", content: "Decision made.")
   ```
   Wait for all shutdown confirmations before cleanup.
   ```
   Teammate(operation: "cleanup")
   ```

7. **Apply Decision**: Set the intensity for all subsequent phases.

8. **Display Decision**:
   ```
   ## Intensity Decision
   - Decision: {intensity_level}
   - Risk Level: {risk_level}
   - Key Factors: {key_factors}
   - Justification: {justification}
   ```

## Error Handling

- Agent Teams unavailable: fall back to Claude solo judgment with explicit reasoning logged.
- Debate times out (>60 seconds): use the last available position from the arbitrator, or default to `standard`.
- No consensus reached: default to `deep` (err on the side of caution).
