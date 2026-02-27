# Shared Phase: Adversarial Red Team (Business Pipeline)

**Applies to**: deep, comprehensive intensity only. Skip for quick and standard.

**Purpose**: Stress-test business content from 3 adversarial perspectives before finalizing. Catches blind spots that collaborative review might miss.

## Variables (set by calling pipeline)

- `CONTENT_DRAFT`: The business content being reviewed
- `BUSINESS_TYPE`: Content type (content, strategy, communication)
- `SELECTED_FRAMEWORKS`: Frameworks chosen in Phase B1.5
- `VALIDATION_RESULTS`: Quantitative validation results from Phase B5.6

## Agent Selection

Based on business type, select 1-3 adversarial agents:

| Business Type | Agents |
|--------------|--------|
| strategy | skeptical-investor-agent, competitor-response-agent, regulatory-risk-agent |
| content (investor-facing) | skeptical-investor-agent, competitor-response-agent |
| content (customer-facing) | competitor-response-agent |
| communication (investor) | skeptical-investor-agent, regulatory-risk-agent |
| communication (regulatory) | regulatory-risk-agent |
| Default | skeptical-investor-agent, competitor-response-agent |

## Steps

1. **Create Red Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "red-team-{YYYYMMDD-HHMMSS}",
     description: "Adversarial red team stress test"
   )
   ```

2. **Create Tasks** (one per selected agent):
   ```
   TaskCreate(
     subject: "Stress test from {perspective} perspective",
     description: "Challenge the business content from {perspective} viewpoint. Focus on weaknesses, risks, and blind spots.",
     activeForm: "Red team: {perspective} challenge"
   )
   ```

3. **Spawn Selected Agents** (all in parallel):

   For each selected agent:
   ```
   Task(
     subagent_type: "{agent-name}",
     team_name: "red-team-{session}",
     name: "{agent-name}",
     prompt: "CONTENT TO STRESS TEST:
     {CONTENT_DRAFT}

     BUSINESS TYPE: {BUSINESS_TYPE}
     FRAMEWORKS USED: {SELECTED_FRAMEWORKS}
     QUANTITATIVE VALIDATION: {VALIDATION_RESULTS}

     Challenge this content from your perspective. Be thorough but constructive.
     Send your challenges to the team lead."
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{task_id}", owner: "{agent-name}")
   ```

5. **Collect Challenges**: Wait for all agents to send their challenges.

6. **Synthesize Red Team Report**:
   Combine all challenges into a unified red team report:
   ```
   RED_TEAM_REPORT:
   - Total Challenges: {sum across all agents}
   - Critical: {count} | High: {count} | Medium: {count} | Low: {count}
   - Investor Perspective: {summary}
   - Competitive Perspective: {summary}
   - Regulatory Perspective: {summary}
   ```

7. **Forward to Content Revision**: Include red team challenges as input for Phase B6.5 (content revision).

8. **Shutdown Team**:
   ```
   FOR each agent in selected_agents:
     SendMessage(type: "shutdown_request", recipient: "{agent-name}", content: "Red team complete.")
   ```
   Wait for all confirmations, then:
   ```
   Teammate(operation: "cleanup")
   ```

9. **Display Results**:
   ```
   ## Adversarial Red Team Results
   - Perspectives: {list of agent perspectives}
   - Total Challenges: {N}
   - Top Challenges:
     1. [{severity}] [{perspective}] {title}
     2. ...
   ```

## Configuration

Settings from `config.red_team`:
- `enabled`: Whether red team is active (default: true)
- `min_intensity`: Minimum intensity to run (default: deep)
- `agents`: List of agents to use (default: [skeptical-investor, competitor-response, regulatory-risk])
- `max_challenges`: Maximum total challenges (default: 10)

## Error Handling

- Agent Teams unavailable: Skip red team, log warning
- Individual agent timeout: Proceed with available results
- All agents fail: Skip red team, note in report
