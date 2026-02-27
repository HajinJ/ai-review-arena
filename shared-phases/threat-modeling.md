# Shared Phase: Threat Modeling (STRIDE 3-Agent Debate)

**Applies to**: deep, comprehensive intensity only. Skip for quick and standard.

**Purpose**: Systematic threat analysis using the STRIDE framework through adversarial debate. A threat modeler proposes threats, a defender challenges them, and an arbitrator synthesizes the final attack surface assessment.

## Variables (set by calling pipeline before including this phase)

- `INTENSITY`: Current intensity level (must be deep or comprehensive)
- `CODE_CONTEXT`: Code files and architecture under review
- `DETECTED_STACK`: Stack detection results from Phase 1
- `STATIC_ANALYSIS_FINDINGS`: Findings from Phase 5.8 (if available)

## Steps

1. **Create Threat Modeling Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "threat-model-{YYYYMMDD-HHMMSS}",
     description: "STRIDE threat modeling debate"
   )
   ```

2. **Create Tasks**:
   ```
   TaskCreate(
     subject: "Identify threats using STRIDE framework",
     description: "Analyze code context and identify threats across all 6 STRIDE categories. Consider static analysis findings if available.",
     activeForm: "Identifying STRIDE threats"
   )

   TaskCreate(
     subject: "Challenge identified threats",
     description: "Review threats from threat-modeler. Challenge each with evidence of existing mitigations, low likelihood, or reduced impact.",
     activeForm: "Challenging threat assessments"
   )

   TaskCreate(
     subject: "Arbitrate threat modeling debate",
     description: "Receive threats and defenses. Synthesize into prioritized attack surface list.",
     activeForm: "Arbitrating threat model"
   )
   ```

3. **Spawn Agents** (in sequence: modeler first, then defender + arbitrator):

   First, spawn threat-modeler:
   ```
   Task(
     subagent_type: "threat-modeler",
     team_name: "threat-model-{session}",
     name: "threat-modeler",
     prompt: "Analyze the following code context using the STRIDE framework.

     CODE CONTEXT:
     {CODE_CONTEXT}

     DETECTED STACK:
     {DETECTED_STACK}

     STATIC ANALYSIS FINDINGS (if available):
     {STATIC_ANALYSIS_FINDINGS}

     Identify up to 10 threats across all STRIDE categories. Focus on realistic, exploitable threats.
     Send your findings to the team lead."
   )
   ```

   After threat-modeler completes, spawn threat-defender and threat-arbitrator:
   ```
   Task(
     subagent_type: "threat-defender",
     team_name: "threat-model-{session}",
     name: "threat-defender",
     prompt: "Review the following threats identified by threat-modeler.

     THREATS:
     {threat_modeler_output}

     CODE CONTEXT:
     {CODE_CONTEXT}

     Challenge each threat with evidence of existing mitigations, low likelihood, or reduced impact.
     Send your defenses to threat-arbitrator."
   )

   Task(
     subagent_type: "threat-arbitrator",
     team_name: "threat-model-{session}",
     name: "threat-arbitrator",
     prompt: "You will receive threats from threat-modeler and defenses from threat-defender.

     THREATS:
     {threat_modeler_output}

     Wait for threat-defender's response, then synthesize the final attack surface assessment.
     Send your consensus to the team lead."
   )
   ```

4. **Assign Tasks**:
   ```
   TaskUpdate(taskId: "{modeler_task}", owner: "threat-modeler")
   TaskUpdate(taskId: "{defender_task}", owner: "threat-defender")
   TaskUpdate(taskId: "{arbitrator_task}", owner: "threat-arbitrator")
   ```

5. **Wait for Consensus**: Wait for threat-arbitrator to send the final attack surface assessment.

6. **Store Results**: Save the threat model to `{SESSION_DIR}/threats/threat-model.json`.

7. **Forward to Phase 6**: Include confirmed threats as additional context for reviewer agents.

8. **Shutdown Team**:
   ```
   SendMessage(type: "shutdown_request", recipient: "threat-modeler", content: "Threat modeling complete.")
   SendMessage(type: "shutdown_request", recipient: "threat-defender", content: "Threat modeling complete.")
   SendMessage(type: "shutdown_request", recipient: "threat-arbitrator", content: "Threat modeling complete.")
   ```
   Wait for all shutdown confirmations, then:
   ```
   Teammate(operation: "cleanup")
   ```

9. **Display Results**:
   ```
   ## Threat Model (STRIDE)
   - Threats Analyzed: {total}
   - Confirmed: {confirmed} | Dismissed: {dismissed} | Flagged: {flagged}
   - Top Threats:
     1. [{severity}] {title} — {attack_surface}
     2. ...
   ```

## Configuration

Settings from `config.threat_modeling`:
- `enabled`: Whether threat modeling is active (default: true)
- `min_intensity`: Minimum intensity to run (default: deep)
- `framework`: Threat modeling framework (default: stride)
- `max_threats`: Maximum threats to analyze (default: 10)
- `debate_timeout`: Maximum time for the debate (default: 300s)

## Error Handling

- Agent Teams unavailable: Skip threat modeling, log warning: "Threat modeling skipped — Agent Teams unavailable"
- Threat modeler timeout: Proceed without threat model
- Defender timeout: Use threat-modeler's uncontested assessment (all threats accepted)
- Arbitrator timeout: Use threat-modeler's assessment minus any conceded threats
