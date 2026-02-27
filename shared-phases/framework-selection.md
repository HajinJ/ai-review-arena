# Shared Phase: Framework Selection Debate (Business Pipeline)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.

**Purpose**: Before creating or analyzing business content, select the most appropriate analysis frameworks through a 3-agent debate. Prevents wasted effort from applying wrong frameworks.

## Variables (set by calling pipeline)

- `BUSINESS_TYPE`: "content", "strategy", or "communication"
- `USER_REQUEST`: The original user request
- `MARKET_CONTEXT`: Market research results from Phase B1
- `BUSINESS_CONTEXT`: Business context from Phase B0.5

## Built-in Framework Database

### Content Frameworks
- **AIDA** (Attention, Interest, Desire, Action): Best for marketing copy, landing pages, sales emails
- **StoryBrand** (Donald Miller): Best for brand messaging, website copy, customer-facing narratives
- **PAS** (Problem, Agitation, Solution): Best for pain-point-driven content, problem-solution articles
- **SCQA** (Situation, Complication, Question, Answer): Best for analytical reports, memos

### Strategy Frameworks
- **Porter's Five Forces**: Best for industry competitive analysis, market entry strategy
- **SWOT** (Strengths, Weaknesses, Opportunities, Threats): Best for strategic planning, situation analysis
- **PESTEL** (Political, Economic, Social, Technological, Environmental, Legal): Best for macro-environment analysis
- **Blue Ocean Strategy**: Best for market creation, differentiation strategy
- **TAM/SAM/SOM**: Best for market sizing, investor presentations
- **Business Model Canvas**: Best for business model design and iteration
- **Value Chain Analysis**: Best for operational strategy, cost optimization

### Communication Frameworks
- **Pyramid Principle** (Barbara Minto): Best for executive communication, structured arguments
- **SPIN Selling**: Best for sales conversations, customer communication
- **STAR** (Situation, Task, Action, Result): Best for case studies, success stories
- **Monroe's Motivated Sequence**: Best for persuasive presentations
- **Aristotle's Appeals** (Ethos, Pathos, Logos): Best for investor communications, public speeches

## Steps

1. **Create Framework Selection Team**:
   ```
   Teammate(
     operation: "spawnTeam",
     team_name: "framework-select-{YYYYMMDD-HHMMSS}",
     description: "Framework selection debate for {BUSINESS_TYPE} content"
   )
   ```

2. **Create Debate Tasks**:
   ```
   TaskCreate(
     subject: "Advocate for comprehensive framework application",
     description: "Argue for the most thorough set of frameworks. Consider the content type, audience, and strategic goals.",
     activeForm: "Advocating for comprehensive frameworks"
   )

   TaskCreate(
     subject: "Advocate for focused framework application",
     description: "Argue for the minimum effective set of frameworks. Avoid framework overload that dilutes focus.",
     activeForm: "Advocating for focused frameworks"
   )

   TaskCreate(
     subject: "Arbitrate framework selection",
     description: "Wait for both advocates. Select up to 3 frameworks that best fit the business type, audience, and goals.",
     activeForm: "Arbitrating framework selection"
   )
   ```

3. **Spawn Debate Agents** (all in parallel):

   ### framework-advocate
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "framework-select-{session}",
     name: "framework-advocate",
     prompt: "You are the Framework Advocate. Argue for the most thorough framework combination.

     BUSINESS TYPE: {BUSINESS_TYPE}
     USER REQUEST: {USER_REQUEST}
     MARKET CONTEXT: {MARKET_CONTEXT}
     BUSINESS CONTEXT: {BUSINESS_CONTEXT}

     AVAILABLE FRAMEWORKS:
     Content: AIDA, StoryBrand, PAS, SCQA
     Strategy: Porter, SWOT, PESTEL, Blue Ocean, TAM/SAM/SOM, Business Model Canvas, Value Chain
     Communication: Pyramid Principle, SPIN, STAR, Monroe's Sequence, Aristotle's Appeals

     Recommend 2-3 frameworks with justification for each. Consider:
     - Content type and audience expectations
     - Strategic depth required
     - Framework complementarity (different perspectives)

     Send your recommendation to framework-arbitrator via SendMessage."
   )
   ```

   ### framework-minimalist
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "framework-select-{session}",
     name: "framework-minimalist",
     prompt: "You are the Framework Minimalist. Argue for the fewest frameworks needed.

     BUSINESS TYPE: {BUSINESS_TYPE}
     USER REQUEST: {USER_REQUEST}
     MARKET CONTEXT: {MARKET_CONTEXT}
     BUSINESS CONTEXT: {BUSINESS_CONTEXT}

     Challenge excessive framework usage. Consider:
     - Is this content really complex enough for multiple frameworks?
     - Would a single well-applied framework be more effective?
     - Does framework stacking create conflicting guidance?

     Recommend 1-2 frameworks maximum. Send to framework-arbitrator via SendMessage."
   )
   ```

   ### framework-arbitrator
   ```
   Task(
     subagent_type: "general-purpose",
     team_name: "framework-select-{session}",
     name: "framework-arbitrator",
     prompt: "You are the Framework Arbitrator. Make the final framework selection.

     Wait for arguments from:
     1. framework-advocate (argues for more frameworks)
     2. framework-minimalist (argues for fewer frameworks)

     Select up to 3 frameworks. For each:
     - Name and brief rationale
     - Primary application point in the content
     - How it complements other selected frameworks

     Send your final selection to the team lead via SendMessage:
     SELECTED_FRAMEWORKS: [{framework1}, {framework2}, ...]
     RATIONALE: {reasoning}
     APPLICATION_MAP: {which framework applies to which content section}"
   )
   ```

4. **Assign Tasks** and wait for arbitrator decision.

5. **Shutdown Team** and cleanup.

6. **Store Selection**: Save to `{SESSION_DIR}/frameworks/selected-frameworks.json`.

7. **Display Selection**:
   ```
   ## Framework Selection
   - Frameworks: {list with rationale}
   - Application Map: {framework -> content section mapping}
   ```

## Configuration

Settings from `config.framework_selection`:
- `enabled`: Whether framework selection is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `debate_timeout`: Maximum time for debate (default: 180s)
- `max_frameworks`: Maximum frameworks to select (default: 3)

## Error Handling

- Agent Teams unavailable: Use default frameworks based on business type (content->AIDA+SCQA, strategy->SWOT+Porter, communication->Pyramid Principle)
- Debate timeout: Use framework-advocate's initial recommendation
- No consensus: Use the most commonly recommended frameworks across both advocates
