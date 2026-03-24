# Review Visualization

Generate Mermaid diagrams for the final review report. These provide at-a-glance understanding of findings and review flow.

## Diagram 1: Findings Severity Distribution

Generate a pie chart showing the distribution of findings by severity:

```mermaid
pie title Finding Severity Distribution
    "Critical" : ${CRITICAL_COUNT}
    "High" : ${HIGH_COUNT}
    "Medium" : ${MEDIUM_COUNT}
    "Low" : ${LOW_COUNT}
```

Only include severity levels with count > 0.

## Diagram 2: Review Flow

Generate a flowchart showing which phases executed and their results:

```mermaid
flowchart TD
    P0[Phase 0: Context] --> P01{Intensity Decision}
    P01 -->|${INTENSITY}| P02[Cost Estimation]
    P02 -->|Approved| P05[Codebase Analysis]
    P05 --> P1[Stack Detection]

    %% Conditional phases based on intensity
    P1 --> P58[Static Analysis]
    P58 --> P6[Agent Team Review]

    P6 --> P65[Auto-Fix]
    P65 --> P66[Test Generation]
    P66 --> P7[Final Report]

    %% Phase results
    P6 -.-> R6[${ACCEPTED_COUNT} accepted\n${REJECTED_COUNT} rejected\n${DISPUTED_COUNT} disputed]
    P7 -.-> R7[${OVERALL_VERDICT}]

    style P6 fill:#f9f,stroke:#333
    style P7 fill:#bbf,stroke:#333
```

Adjust the flow based on actual intensity:
- `quick`: Show only Phase 0 → 0.1-Pre → 0.5
- `standard`: Show Phase 0 through 7 (skip 2, 2.9, 3, 4, 5.9)
- `deep`: Show all phases including 2, 2.9, 3, 5.9
- `comprehensive`: Show all phases including 4

## Diagram 3: Agent Participation

Generate a diagram showing which agents participated and their finding counts:

```mermaid
graph LR
    subgraph "Round 1: Initial Review"
        SR[Security\n${SEC_FINDINGS} findings]
        BD[Bug Detector\n${BUG_FINDINGS} findings]
        AR[Architecture\n${ARCH_FINDINGS} findings]
        PR[Performance\n${PERF_FINDINGS} findings]
    end

    subgraph "Round 2: Cross-Examination"
        SR --> DA[Debate Arbitrator]
        BD --> DA
        AR --> DA
        PR --> DA
    end

    subgraph "Round 3: Defense"
        DA --> CON{Consensus}
    end

    CON -->|Accepted| ACC[${ACCEPTED_COUNT}]
    CON -->|Rejected| REJ[${REJECTED_COUNT}]
    CON -->|Disputed| DIS[${DISPUTED_COUNT}]
```

## Diagram 4: Intensity Decision Rationale

When intensity rationale is available, show the decision factors:

```mermaid
mindmap
  root((${INTENSITY}))
    Complexity
      ${COMPLEXITY_FACTOR}
    Security Impact
      ${SECURITY_FACTOR}
    Scope Size
      ${SCOPE_FACTOR}
    Escalation Triggers
      ${ESCALATION_FACTOR}
```

## Usage in Pipeline

Phase 7 (Final Report) generates these diagrams by:

1. Reading consensus findings JSON for counts
2. Reading signal log for agent participation data
3. Reading intensity rationale for decision factors
4. Substituting variables into Mermaid templates
5. Appending diagrams to the markdown report

The `generate-report.sh` script handles the template substitution.
