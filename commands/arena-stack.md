---
description: "Detect project technology stack and optionally search best practices for each technology"
argument-hint: "[path] [--deep] [--search-practices] [--output json|markdown] [--skip-cache]"
allowed-tools: [Bash, Read, Glob, Grep, WebSearch]
---

# AI Review Arena - Stack Detection

You detect the technology stack of a project and optionally search for best practices for each detected technology. This is a focused utility command that can be used standalone or as input to `/arena` and `/arena-research`.

## Constants

```
PLUGIN_DIR="~/.claude/plugins/ai-review-arena"
SCRIPTS_DIR="${PLUGIN_DIR}/scripts"
CONFIG_DIR="${PLUGIN_DIR}/config"
CACHE_DIR="${PLUGIN_DIR}/cache"
DEFAULT_CONFIG="${CONFIG_DIR}/default-config.json"
```

## Argument Parsing

Parse `$ARGUMENTS` to determine detection scope and options.

**Steps:**

1. Parse all arguments and flags:
   - Extract path argument (default: project root via `git rev-parse --show-toplevel 2>/dev/null || pwd`)
   - Check for `--deep` flag (default: false; enables deeper analysis of dependency files and configs)
   - Check for `--search-practices` flag (default: false; triggers Phase 2)
   - Extract `--output` format (default: "markdown", options: "json", "markdown")
   - Check for `--skip-cache` flag (default: false)

2. Validate the target path:
   ```bash
   TARGET_PATH="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
   if [ ! -d "${TARGET_PATH}" ]; then
     echo "error: path does not exist: ${TARGET_PATH}"
   else
     echo "target: ${TARGET_PATH}"
   fi
   ```

3. Load configuration for cache settings:
   ```bash
   cat "${PLUGIN_DIR}/config/default-config.json"
   ```

---

## Phase 1: Stack Detection

Detect the project's technology stack.

**Steps:**

1. Check cache first (unless `--skip-cache`):
   ```bash
   bash "${SCRIPTS_DIR}/cache-manager.sh" check "${TARGET_PATH}" stack detection --ttl 7
   ```

2. If cache is fresh and not `--skip-cache`:
   - Read cached stack profile
   - Display results (skip to step 6)

3. If cache is stale or `--skip-cache`, run detection:
   ```bash
   # With --deep flag:
   bash "${SCRIPTS_DIR}/detect-stack.sh" "${TARGET_PATH}" --deep --output json

   # Without --deep flag:
   bash "${SCRIPTS_DIR}/detect-stack.sh" "${TARGET_PATH}" --output json
   ```

4. Parse JSON output to extract:
   - `platform`: server, mobile (ios/android), web, game, desktop, embedded
   - `languages`: detected programming languages with versions
   - `frameworks`: detected frameworks with versions
   - `databases`: detected database systems with versions
   - `infrastructure`: Docker, Kubernetes, CI/CD tools, cloud providers
   - `build_tools`: build systems, package managers, task runners
   - `testing`: test frameworks and tools
   - `linting`: code quality tools

5. Cache detection results:
   ```bash
   echo '${STACK_JSON}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${TARGET_PATH}" stack detection --ttl 7
   ```

6. Display results based on `--output` format:

   **Markdown output (default):**
   ```
   ## Stack Detection Results

   **Project:** {basename of TARGET_PATH}
   **Platform:** {platform}
   **Detection:** {cache status: cached (age) / fresh scan}

   ### Languages
   | Language | Version | Confidence |
   |----------|---------|------------|
   | {language} | {version} | {high/medium/low} |

   ### Frameworks
   | Framework | Version | Category |
   |-----------|---------|----------|
   | {framework} | {version} | {web/api/orm/testing/etc.} |

   ### Databases
   | Database | Version | Type |
   |----------|---------|------|
   | {database} | {version} | {relational/nosql/cache/search} |

   ### Infrastructure
   | Tool | Category | Config File |
   |------|----------|------------|
   | {tool} | {container/orchestration/ci-cd/cloud} | {file path} |

   ### Build & Quality Tools
   | Tool | Purpose |
   |------|---------|
   | {tool} | {build/package/lint/format/test} |

   ### Summary
   - Total technologies: {count}
   - Primary stack: {language} + {framework} + {database}
   - Platform classification: {platform description}
   ```

   **JSON output:**
   ```json
   {
     "project": "...",
     "target_path": "...",
     "platform": "...",
     "detection_source": "cache|scan",
     "languages": [{"name": "...", "version": "...", "confidence": "..."}],
     "frameworks": [{"name": "...", "version": "...", "category": "..."}],
     "databases": [{"name": "...", "version": "...", "type": "..."}],
     "infrastructure": [{"name": "...", "category": "...", "config_file": "..."}],
     "build_tools": [{"name": "...", "purpose": "..."}],
     "testing": [{"name": "...", "type": "..."}],
     "summary": {
       "total_technologies": 0,
       "primary_stack": "...",
       "platform_classification": "..."
     }
   }
   ```

**Error Handling:**
- If detect-stack.sh fails or is not found:
  Fall back to manual detection by scanning for common project files:
  ```bash
  # Check for common configuration files
  ls "${TARGET_PATH}/package.json" 2>/dev/null && echo "node:detected"
  ls "${TARGET_PATH}/pom.xml" 2>/dev/null && echo "java-maven:detected"
  ls "${TARGET_PATH}/build.gradle" "${TARGET_PATH}/build.gradle.kts" 2>/dev/null && echo "java-gradle:detected"
  ls "${TARGET_PATH}/requirements.txt" "${TARGET_PATH}/pyproject.toml" "${TARGET_PATH}/setup.py" 2>/dev/null && echo "python:detected"
  ls "${TARGET_PATH}/go.mod" 2>/dev/null && echo "go:detected"
  ls "${TARGET_PATH}/Cargo.toml" 2>/dev/null && echo "rust:detected"
  ls "${TARGET_PATH}/Gemfile" 2>/dev/null && echo "ruby:detected"
  ls "${TARGET_PATH}/composer.json" 2>/dev/null && echo "php:detected"
  ls "${TARGET_PATH}/Package.swift" 2>/dev/null && echo "swift:detected"
  ls "${TARGET_PATH}/pubspec.yaml" 2>/dev/null && echo "flutter:detected"
  ls "${TARGET_PATH}/Dockerfile" 2>/dev/null && echo "docker:detected"
  ls "${TARGET_PATH}/.github/workflows/"*.yml 2>/dev/null && echo "github-actions:detected"
  ```
  Then use Glob and Read tools to extract version information from detected config files:
  ```
  Glob(pattern: "${TARGET_PATH}/package.json")
  Read(file_path: "${TARGET_PATH}/package.json")
  ```
  Parse dependencies to identify frameworks and libraries.

- If target path does not exist: report error and exit.
- If target path is empty (no recognizable project files): report "No technologies detected" and suggest providing `--deep` flag or a different path.

---

## Phase 2: Best Practice Search (Optional)

Only execute if `--search-practices` flag is provided.

**Steps:**

1. For each detected technology, run the search-best-practices script:
   ```bash
   bash "${SCRIPTS_DIR}/search-best-practices.sh" "<technology>" --config "${CONFIG_DIR}/tech-queries.json"
   ```

2. Parse script output:
   - If `cached=true`: read the cached content
   - If `cached=false`: the script returns `search_queries` array

3. For non-cached technologies, execute WebSearch with each query:
   - Substitute `{year}` with the current year (2026)
   - Substitute `{version}` with the detected version
   ```
   WebSearch(query: "{query_with_substitutions}")
   ```

4. Compile results per technology.

5. Cache results (unless `--skip-cache`):
   ```bash
   echo '${RESEARCH_CONTENT}' | bash "${SCRIPTS_DIR}/cache-manager.sh" write "${TARGET_PATH}" research "<technology>-best-practices" --ttl 3
   ```

6. Display compiled best practices:

   **Markdown output:**
   ```
   ## Best Practices by Technology

   ### {Technology 1} (v{version})

   **Key Practices:**
   - {practice 1}
   - {practice 2}
   - {practice 3}

   **Performance Tips:**
   - {tip 1}
   - {tip 2}

   **Security Considerations:**
   - {consideration 1}
   - {consideration 2}

   **Source:** {cached / WebSearch query}

   ---

   ### {Technology 2} (v{version})
   ...
   ```

   **JSON output:**
   ```json
   {
     "best_practices": {
       "{technology}": {
         "version": "...",
         "source": "cache|web_search",
         "practices": ["..."],
         "performance": ["..."],
         "security": ["..."]
       }
     }
   }
   ```

**Error Handling:**
- If search-best-practices.sh fails for a technology: use WebSearch directly with the technology name:
  ```
  WebSearch(query: "{technology} best practices production 2026")
  ```
- If WebSearch returns no results: note "{technology}: No best practices found" and continue to next.
- If all searches fail: report "Best practice search unavailable" and display stack detection results only.

---

## Error Handling Summary

### Script Failures
- **detect-stack.sh missing**: Fall back to manual file detection (Glob + Read)
- **search-best-practices.sh missing**: Fall back to direct WebSearch
- **cache-manager.sh missing**: Proceed without caching, warn user

### Tool Failures
- **Bash timeout**: Retry once with increased timeout, then fall back
- **WebSearch unavailable**: Report technologies without best practices
- **Read tool failure**: Skip the affected file, continue with others

### Edge Cases
- **Empty project directory**: Report "No project files detected"
- **Monorepo detection**: If multiple project roots detected, list all and ask user which to analyze
- **Binary-only projects**: Report detected binaries but note limited analysis capability
- **Symlink handling**: Follow symlinks but detect circular references

### Cache Behavior
- Cache is shared with `/arena` and `/arena-research` commands
- `--skip-cache` forces fresh detection but still writes to cache
- Cache TTL for stack detection: 7 days (from config `cache.ttl_overrides.stack`)
- Cache TTL for best practices: 3 days (from config `cache.default_ttl_days`)
- Cache location: `${CACHE_DIR}/` managed by cache-manager.sh
