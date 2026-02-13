---
description: "Pre-implementation research - technology best practices, compliance guidelines, Figma analysis"
argument-hint: "[feature-description] [--figma <url>] [--stack auto|<tech-list>] [--compliance] [--ttl <days>] [--skip-cache] [--output markdown|json]"
allowed-tools: [Bash, Read, WebSearch, WebFetch, Glob, Grep]
---

# AI Review Arena - Pre-Implementation Research

You perform standalone pre-implementation research to gather technology best practices, compliance guidelines, and Figma design analysis. This is a lighter-weight command that runs without Agent Teams -- it produces a research brief that can be used independently or fed into `/arena` or `/multi-review`.

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
CACHE_DIR="${PLUGIN_DIR}/cache"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
SESSION_DIR="/tmp/ai-review-arena/$(date +%Y%m%d-%H%M%S)"
```

## Argument Parsing

Parse `$ARGUMENTS` to determine the research scope and options.

**Steps:**

1. Parse all flags:
   - Extract `--figma <url>` if present
   - Extract `--stack` value (default: "auto")
     - `auto`: run detect-stack.sh to auto-detect
     - Comma-separated list (e.g., `springboot,redis,mysql`): use provided technologies
   - Check for `--compliance` flag (default: auto-detect from feature description)
   - Extract `--ttl <days>` override for cache TTL (default: from config)
   - Check for `--skip-cache` flag (default: false)
   - Extract `--output` format (default: "markdown", options: "markdown", "json")
   - Remaining arguments are treated as the feature description

2. Load configuration (same resolution order as arena.md):
   ```bash
   cat "${PLUGIN_DIR}/config/default-config.json"
   ```
   ```bash
   test -f ~/.claude/.ai-review-arena.json && cat ~/.claude/.ai-review-arena.json || echo "{}"
   ```
   ```bash
   PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
   test -f "${PROJECT_ROOT}/.ai-review-arena.json" && cat "${PROJECT_ROOT}/.ai-review-arena.json" || echo "{}"
   ```

3. Create session directory:
   ```bash
   mkdir -p "${SESSION_DIR}/research" "${SESSION_DIR}/compliance"
   ```

4. Display research plan:
   ```
   ## Research Plan
   - Stack detection: {auto / provided list}
   - Feature: {feature description or "general"}
   - Compliance: {enabled/disabled}
   - Figma: {url or "not provided"}
   - Cache: {enabled/disabled}, TTL: {days}d
   - Output: {markdown/json}
   ```

---

## Phase 1: Stack Detection

Detect or accept the project technology stack.

**If `--stack auto` (default):**

1. Check cache first (unless `--skip-cache`):
   ```bash
   bash "${SCRIPTS_DIR}/cache-manager.sh" check "${PROJECT_ROOT}" stack detection --ttl 7
   ```

2. If cache is fresh:
   - Read cached stack profile
   - Parse technologies list

3. If cache is stale or `--skip-cache`:
   ```bash
   bash "${SCRIPTS_DIR}/detect-stack.sh" "${PROJECT_ROOT}" --deep --output json
   ```

4. Cache the detection results:
   ```bash
   echo '${STACK_JSON}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" stack detection --ttl 7
   ```

**If `--stack <tech-list>` (explicit list):**

1. Parse the comma-separated list (e.g., `springboot,redis,mysql`)
2. Construct a minimal stack profile JSON with the listed technologies
3. Skip cache for user-provided stacks

**Display stack results:**
```
## Detected Technologies
| Technology | Version | Category |
|-----------|---------|----------|
| {tech} | {version or "N/A"} | {language/framework/database/infra} |
```

**Error Handling:**
- If detect-stack.sh fails: attempt manual detection via Glob for common config files (package.json, pom.xml, build.gradle, requirements.txt, go.mod, Cargo.toml, Gemfile, composer.json).
- If no technologies detected and none provided: warn and exit with suggestion to use `--stack <tech-list>`.

---

## Phase 2: Best Practice Research

Gather best practices for each detected technology.

**Steps:**

1. For each technology in the stack:
   a. Run the search-best-practices script:
      ```bash
      bash "${SCRIPTS_DIR}/search-best-practices.sh" "<technology>" --config "${CONFIG_DIR}/tech-queries.json"
      ```

   b. Parse script output:
      - If `cached=true`: read the cached content from the output path
      - If `cached=false`: the script returns a `search_queries` array

   c. For non-cached technologies, execute WebSearch with each query:
      - Substitute `{year}` with the current year (2026)
      - Substitute `{version}` with the detected version
      ```
      WebSearch(query: "{query_with_substitutions}")
      ```

   d. Compile search results into structured research content for this technology:
      - Key best practices (bullet points)
      - Common pitfalls and anti-patterns
      - Recommended patterns and implementations
      - Performance considerations
      - Security considerations

   e. Cache the results (unless `--skip-cache`):
      ```bash
      echo '${RESEARCH_CONTENT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" research "<technology>-best-practices" --ttl ${TTL_DAYS}
      ```

2. If a feature description was provided in `$ARGUMENTS`:
   a. Extract feature keywords
   b. Search for feature-specific implementation patterns:
      ```
      WebSearch(query: "<feature> implementation best practices <primary_framework> 2026")
      WebSearch(query: "<feature> common mistakes pitfalls <primary_language> 2026")
      ```
   c. Include results in a dedicated "Feature-Specific Research" section

3. Compile all research into a unified brief.

4. Display research results:
   ```
   ## Best Practice Research

   ### {Technology 1} (v{version})
   **Key Best Practices:**
   - {practice 1}
   - {practice 2}
   - {practice 3}

   **Common Pitfalls:**
   - {pitfall 1}
   - {pitfall 2}

   **Recommended Patterns:**
   - {pattern 1}
   - {pattern 2}

   ### {Technology 2} (v{version})
   ...

   ### Feature-Specific: {Feature Description}
   **Implementation Patterns:**
   - {pattern 1}
   - {pattern 2}

   **Mistakes to Avoid:**
   - {mistake 1}
   - {mistake 2}
   ```

**Error Handling:**
- If search-best-practices.sh fails for a technology: use WebSearch directly with generic queries.
- If WebSearch returns no results for a query: skip that query and note the gap.
- If all research fails for a technology: note "No research available" and continue.

---

## Phase 3: Compliance Detection (Optional)

Execute if `--compliance` flag is set, or if auto-detection finds matching patterns.

**Auto-Detection Logic:**
1. Extract keywords from:
   - Feature description (from `$ARGUMENTS`)
   - Changed file names (if in a git repo):
     ```bash
     git diff --staged --name-only 2>/dev/null || git diff HEAD --name-only 2>/dev/null || echo ""
     ```
   - Detected technology stack (e.g., "ios" platform triggers Apple guidelines)

2. If any keywords match patterns in compliance-rules.json, auto-enable compliance.

**Steps:**

1. Run compliance guideline search:
   ```bash
   bash "${SCRIPTS_DIR}/search-guidelines.sh" "<keywords>" "<detected-platform>" --config "${CONFIG_DIR}/compliance-rules.json"
   ```

2. Parse output: for each matched guideline:
   a. If `cached=true`: include cached content
   b. If `cached=false`: execute WebSearch:
      ```
      WebSearch(query: "{search_query with {year} substituted to 2026}")
      ```
   c. Cache new results:
      ```bash
      echo '${GUIDELINE_CONTENT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${PROJECT_ROOT}" compliance "<guideline-name>" --ttl 7
      ```

3. Compile compliance requirements with status indicators.

4. Display compliance results:
   ```
   ## Compliance Guidelines

   ### {Feature Pattern}: {Pattern Name}
   | Guideline | Platform | Requirements | Source |
   |-----------|----------|-------------|--------|
   | {guideline_name} | {platform} | {count} requirements | {cached/web search} |

   ### Detailed Requirements
   #### {Guideline 1}
   - {requirement 1}
   - {requirement 2}
   - {requirement 3}

   #### {Guideline 2}
   ...
   ```

**Error Handling:**
- If search-guidelines.sh fails: fall back to manual keyword matching by reading compliance-rules.json directly with Read tool.
- If WebSearch fails for a guideline: include requirement name with "unverified" tag.
- If no patterns match: report "No specific compliance requirements detected for this feature."

---

## Phase 4: Figma Analysis (Optional)

Only execute if `--figma <url>` was provided.

**Steps:**

1. Load Figma MCP tools using ToolSearch:
   ```
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_screenshot")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_metadata")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_design_context")
   ToolSearch(query: "select:mcp__claude_ai_Figma__get_variable_defs")
   ```

2. Fetch design metadata:
   ```
   mcp__claude_ai_Figma__get_metadata(url: "{figma_url}")
   ```

3. Fetch screenshot:
   ```
   mcp__claude_ai_Figma__get_screenshot(url: "{figma_url}")
   ```

4. Get design context:
   ```
   mcp__claude_ai_Figma__get_design_context(url: "{figma_url}")
   ```

5. Get variable definitions:
   ```
   mcp__claude_ai_Figma__get_variable_defs(url: "{figma_url}")
   ```

6. Analyze and display:
   ```
   ## Figma Design Analysis

   ### Components
   | Component | Type | Variants |
   |-----------|------|----------|
   | {name} | {type} | {variant count} |

   ### Design Tokens
   - Colors: {count} ({list of key colors})
   - Typography: {count} styles
   - Spacing: {count} values

   ### Layout Structure
   - {layout description}
   - Responsive indicators: {responsive notes}

   ### Interaction States
   - {state 1}: {description}
   - {state 2}: {description}

   ### Accessibility Notes
   - Contrast: {contrast observations}
   - Text sizing: {sizing observations}
   - Touch targets: {target size observations}
   ```

7. Save analysis:
   ```bash
   echo '${FIGMA_ANALYSIS}' > "${SESSION_DIR}/research/figma-analysis.md"
   ```

**Error Handling:**
- If Figma MCP tools fail to load: report error, suggest using Figma URL directly in browser.
- If URL is invalid: report "Invalid Figma URL" and skip.
- If partial data: use what is available and note gaps.

---

## Phase 5: Output

Compile all gathered research into a final output.

**Steps:**

1. Compile all sections into a unified document:
   - Stack profile
   - Best practice research (per technology)
   - Feature-specific research (if feature description provided)
   - Compliance requirements (if enabled)
   - Figma analysis (if provided)

2. Format based on `--output` flag:

   **Markdown output (default):**
   ```markdown
   # Pre-Implementation Research Brief

   **Date:** {timestamp}
   **Project:** {project_root basename}
   **Feature:** {feature description or "General"}

   ---

   ## Technology Stack
   {stack table}

   ---

   ## Best Practices
   {per-technology research sections}

   ---

   ## Feature Research
   {feature-specific findings, if applicable}

   ---

   ## Compliance Requirements
   {compliance sections, if applicable}

   ---

   ## Design Analysis
   {Figma analysis, if applicable}

   ---

   ## Research Sources
   - {list of WebSearch queries used and cache hits}
   ```

   **JSON output:**
   ```json
   {
     "timestamp": "...",
     "project": "...",
     "feature": "...",
     "stack": { ... },
     "research": { ... },
     "compliance": { ... },
     "figma": { ... },
     "sources": [ ... ]
   }
   ```

3. Display the compiled output to the user.

4. Save to session directory:
   ```bash
   echo '${OUTPUT}' > "${SESSION_DIR}/research/research-brief.md"
   # or for JSON:
   echo '${OUTPUT_JSON}' > "${SESSION_DIR}/research/research-brief.json"
   ```

5. Display session reference:
   ```
   ## Research Complete
   - Session: ${SESSION_DIR}
   - Brief: ${SESSION_DIR}/research/research-brief.{md|json}
   - Use with arena: `/arena --phase review` (research context will be loaded from cache)
   ```

---

## Error Handling

### Overall Strategy
- Each phase is independent: failure in one phase does not prevent other phases from running.
- Cache failures are non-fatal: fall back to live searches.
- WebSearch failures are non-fatal: note the gap and continue.
- Only a complete failure of all phases should result in an error exit.

### Specific Error Cases
- **detect-stack.sh not found or not executable**: Fall back to manual file detection using Glob.
- **search-best-practices.sh failure**: Use WebSearch directly with technology name.
- **search-guidelines.sh failure**: Read compliance-rules.json directly and match keywords manually.
- **Figma MCP tools unavailable**: Skip Figma analysis with warning.
- **No git repository**: Skip changed-file detection, rely on user-provided feature description.
- **jq not installed**: Parse JSON manually where possible, warn about reduced functionality.

### Cache Behavior
- Cache is shared with `/arena` command: research done here will be available to `/arena`.
- `--skip-cache` forces fresh lookups but still writes to cache for future use.
- `--ttl` override applies to all cache writes in this session.
- Cache location: `${CACHE_DIR}/` managed by cache-manager.sh.
