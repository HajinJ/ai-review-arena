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

5.5. **Playwright MCP Browser Verification** (if available):

   Check for Playwright MCP:
   ```
   ToolSearch(query: "playwright browser")
   ```

   If Playwright MCP is found:

   a. **Dev Server Detection**: Check if a dev server is running on configured ports:
      ```bash
      for port in $(echo "$DEV_SERVER_DETECT_PORTS" | jq -r '.[]'); do
        curl -s -o /dev/null -w "%{http_code}" "http://localhost:${port}/" --connect-timeout 2 && echo "port:${port}:running" || echo "port:${port}:down"
      done
      ```
      If no server detected, log: "No dev server running — skipping Playwright browser verification." and skip to Step 6.

   b. **Navigate to Changed Routes**: For each frontend file that maps to a route:
      ```
      Extract route from file path heuristics:
        - src/pages/about.tsx → /about
        - src/app/dashboard/page.tsx → /dashboard
        - src/routes/settings.svelte → /settings
        - components without route mapping → use root "/" or Storybook URL

      For each route:
        playwright_navigate(url: "{dev_server_url}{route}")
      ```
      Timeout: `navigation_timeout_ms` (default 10000ms). On timeout → skip that page and continue.

   c. **Accessibility Snapshot**: Capture accessibility tree to verify DOM structure:
      ```
      snapshot = playwright_snapshot()
      ```
      Cross-reference CSS selectors from Step 3 against the snapshot:
      - For each extracted selector: check if it exists in the accessibility tree
      - Report: "Selector `{selector}` — {found|NOT FOUND in DOM}"
      - Selectors in code but not in DOM may indicate rendering issues

   d. **Responsive Screenshots**: Capture screenshots at configured breakpoints:
      ```
      FOR each breakpoint in config.visual_verification.responsive_breakpoints:
        playwright_screenshot(
          width: breakpoint.width,
          height: breakpoint.height,
          fullPage: config.screenshot_capture.full_page
        )
        Save to: "visual-baselines/{route_slug}_{breakpoint.name}.{format}"
      ```
      Timeout: `screenshot_timeout_ms` per screenshot. On failure → skip that breakpoint.

   e. **Baseline Comparison**: If baselines exist in cache:
      ```bash
      BASELINE_KEY="{route_slug}_{breakpoint_name}"
      bash "${SCRIPTS_DIR}/cache-manager.sh" read "${PROJECT_ROOT}" \
        "${BASELINE_CACHE_CATEGORY}" "${BASELINE_KEY}" > /dev/null 2>&1
      ```
      - If baseline found: compare dimensions and note visual changes
      - If no baseline: store current screenshot as new baseline:
        ```bash
        cat screenshot.png | bash "${SCRIPTS_DIR}/cache-manager.sh" write \
          "${PROJECT_ROOT}" "${BASELINE_CACHE_CATEGORY}" "${BASELINE_KEY}" \
          --ttl ${BASELINE_TTL_DAYS}
        ```

   f. **DOM Selector Cross-Validation**:
      Compare selectors extracted from code (Step 3) against selectors found in DOM (Step 5.5c):
      ```
      FOR each selector in extracted_selectors:
        IF selector NOT found in DOM snapshot:
          Report: "⚠ Selector '{selector}' exists in code but not rendered in DOM"
          visual_risk = "high" (potential rendering bug)
      ```

   If Playwright MCP is NOT found:
   - Log: "Playwright MCP not available — using static CSS selector analysis (fallback)."
   - Continue with existing Step 3-5 static analysis (current behavior preserved).

   **Error Handling**:
   - Dev server not running → skip Playwright steps entirely
   - Navigation timeout → skip that specific page, continue with others
   - Screenshot failure → skip that breakpoint, continue with others
   - Playwright MCP tool call error → fall back to static analysis

6. **Display Results**:
   ```
   ## Visual Verification (Phase 6.7)
   - Frontend files affected: {N}
   - Components with visual changes: {list}
   - High-risk visual changes: {count}
   - Visual feedback tools: {agentation: available/unavailable, storybook: available/unavailable, playwright: available/unavailable}

   ### Verification Checklist
   {generated checklist}

   ### CSS Selectors to Monitor
   {selector table}

   ### Playwright Browser Verification (if executed)
   - Dev server: {url} (port {port})
   - Pages verified: {count}
   - Responsive screenshots: {breakpoint_count} breakpoints x {page_count} pages
   - DOM selector mismatches: {count} (selectors in code but not in DOM)
   - Baseline comparisons: {new_count} new, {compared_count} compared
   ```

## Configuration

Settings from `config.visual_verification`:
- `enabled`: Whether visual verification is active (default: true)
- `min_intensity`: Minimum intensity to run (default: standard)
- `risk_threshold`: Minimum visual risk to include in checklist (default: medium)
- `agentation_mcp`: Auto-detect Agentation MCP (default: true)
- `storybook_integration`: Check for Storybook (default: true)
- `output_mode`: Selector output detail level — compact|standard|detailed|forensic (default: standard)

### Playwright Integration (`config.visual_verification.playwright_integration`)
- `enabled`: Enable Playwright MCP browser verification (default: true)
- `dev_server_url`: Base URL for the dev server (default: "http://localhost:3000")
- `dev_server_detect_ports`: Ports to auto-detect running dev servers (default: [3000, 5173, 8080, 4200])
- `navigation_timeout_ms`: Max wait for page navigation (default: 10000)
- `screenshot_timeout_ms`: Max wait per screenshot capture (default: 5000)

### Screenshot Capture (`config.visual_verification.screenshot_capture`)
- `enabled`: Enable screenshot capture (default: true)
- `format`: Image format — png|jpeg (default: "png")
- `full_page`: Capture full scrollable page (default: false)
- `store_baselines`: Save screenshots as baselines for future comparison (default: true)
- `baseline_cache_category`: Cache category name for baselines (default: "visual-baselines")
- `baseline_ttl_days`: TTL for stored baselines (default: 30)

### Responsive Breakpoints (`config.visual_verification.responsive_breakpoints`)
Array of `{name, width, height}` objects defining viewport sizes for responsive testing.
Defaults: mobile (375x812), tablet (768x1024), desktop (1024x768), wide (1440x900)

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
- Playwright MCP unavailable: Fall back to static analysis (Steps 3-5), skip browser verification
- Dev server not running: Skip Playwright browser verification, log message, continue with static analysis
- Page navigation timeout: Skip that specific page, continue with remaining pages
- Screenshot capture failure: Skip that breakpoint, continue with remaining breakpoints
- Playwright tool call error: Fall back to static analysis for that page
