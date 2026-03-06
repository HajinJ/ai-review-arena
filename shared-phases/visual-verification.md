# Shared Phase: Visual Verification (Code Pipeline)

**Applies to**: standard, deep, comprehensive intensity. Skip for quick.
**Prerequisite**: Phase 6.6 (Test Generation) must complete first.

**Purpose**: Verify frontend changes visually using structured feedback tools. The key insight from C2 (visual-feedback-tools) is that frontend AI coding bottlenecks stem from feedback delivery accuracy, not model performance. This phase captures CSS selectors and DOM context to provide precise visual regression data.

**Philosophy**: "AI 코딩 도구에 불만이 있다면 도구를 바꾸기 전에 피드백 전달 방식을 먼저 개선한다" (C2)

## Variables (set by calling pipeline)

- `FILES_CHANGED`: List of files in the review scope
- `DETECTED_STACK`: Stack detection results from Phase 1
- `ACCEPTED_FINDINGS`: Confirmed findings from Phase 6 debate
- `PROJECT_ROOT`: Project root directory

## Steps

1. **Check Applicability**:

   Determine if the changed files include frontend code:
   ```
   frontend_files = FILES_CHANGED.filter(f =>
     f.extension in ["tsx", "jsx", "vue", "svelte", "html", "css", "scss"] OR
     f.path matches "*component*" OR "*page*" OR "*layout*" OR "*view*"
   )
   ```

   If no frontend files, skip this phase with: "No frontend files in scope — skipping visual verification."

2. **Detect Visual Feedback Tools**:

   Check for available visual feedback infrastructure:

   a. **Agentation MCP Detection**:
      ```
      ToolSearch(query: "agentation")
      ```
      If found: `agentation_available = true`
      If not found: Check if npm package is installed:
      ```bash
      test -f "${PROJECT_ROOT}/node_modules/agentation/package.json" && echo "installed" || echo "not_installed"
      ```

   b. **Screenshot/Browser Tools**:
      ```
      ToolSearch(query: "screenshot browser playwright")
      ```
      Record available screenshot capabilities.

   c. **Storybook Detection**:
      ```bash
      test -f "${PROJECT_ROOT}/.storybook/main.js" -o -f "${PROJECT_ROOT}/.storybook/main.ts" && echo "storybook:available" || echo "storybook:unavailable"
      ```

3. **CSS Selector Extraction** (Core C2 philosophy):

   For each frontend finding with a suggestion that modifies UI:
   ```
   FOR each finding in ACCEPTED_FINDINGS where finding.file in frontend_files:
     Extract from finding context:
     - Component name (from file path or JSX/TSX export)
     - CSS selectors affected by the suggested fix
     - Parent component context (1 level up)
     - Relevant CSS classes / Tailwind utilities

     Generate structured feedback:
     {
       "component": "<ComponentName>",
       "file": "<file_path>",
       "selectors": ["<css_selector_1>", "<css_selector_2>"],
       "change_type": "style|layout|visibility|interaction",
       "finding_id": "<finding_id>",
       "visual_risk": "low|medium|high"
     }
   ```

   **Visual risk assessment**:
   - `high`: Layout changes (flexbox/grid modifications, positioning), visibility toggles, z-index changes
   - `medium`: Color/typography changes, spacing adjustments, responsive breakpoint changes
   - `low`: Icon swaps, text content changes, minor padding tweaks

4. **Visual Regression Checklist**:

   Generate a verification checklist based on extracted selectors:
   ```
   FOR each visual change with risk >= medium:
     Generate checklist item:
     - [ ] Verify {component} at {selector}: {change_description}
     - [ ] Check responsive behavior at mobile (375px) and tablet (768px)
     - [ ] Verify no unintended side effects on parent component
   ```

5. **Agentation Integration** (if available):

   If Agentation MCP is detected:
   ```
   Suggest to user:
   "Agentation MCP detected. For precise visual verification:
    1. Run the dev server
    2. Click on affected components in the browser
    3. Agentation will extract exact CSS selectors
    4. Compare extracted selectors with the expected changes above"
   ```

6. **Display Results**:
   ```
   ## Visual Verification (Phase 6.7)
   - Frontend files affected: {N}
   - Components with visual changes: {list}
   - High-risk visual changes: {count}
   - Visual feedback tools: {agentation: available/unavailable, storybook: available/unavailable}

   ### Verification Checklist
   {generated checklist}

   ### CSS Selectors to Monitor
   {selector table}
   ```

## Configuration

Settings from `config.visual_verification`:
- `enabled`: Whether visual verification is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `risk_threshold`: Minimum visual risk to include in checklist (default: medium)
- `agentation_mcp`: Auto-detect Agentation MCP (default: true)
- `storybook_integration`: Check for Storybook (default: true)
- `output_mode`: Selector output detail level — compact|standard|detailed|forensic (default: standard)

## Output Modes (C2 Agentation Philosophy)

| Mode | Content | Use Case |
|------|---------|----------|
| compact | Selector + change description | Quick review |
| standard | Selector + DOM context + change type | General visual review |
| detailed | Selector + computed styles + layout info | Complex layout debugging |
| forensic | Full computed style diff + animation states | Animation/transition bugs |

## Error Handling

- No frontend files: Skip phase entirely (not an error)
- Agentation unavailable: Fall back to static CSS selector analysis from code
- Cannot determine component structure: Generate generic selectors from file paths
- Storybook unavailable: Skip Storybook integration, continue with other checks
