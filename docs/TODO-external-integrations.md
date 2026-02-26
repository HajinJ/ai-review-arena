# TODO: External Integration Improvements

Research completed 2026-02-26. These items require external API changes or features that are not yet stable enough for production integration.

---

## 1. Codex Sub-Agent Integration

**Status**: Experimental (feature flag gated)
**Priority**: High
**Blocked by**: Codex multi-agent feature graduating from experimental

### Current State (Feb 2026)
- Codex CLI sub-agents implemented via PR #3655, tracking issue #2604 closed as COMPLETED (2026-02-23)
- Still gated behind experimental flag (`/experimental` menu or `~/.codex/config.toml` `[features] multi_agent = true`)
- Not yet GA -- OpenAI has not removed the experimental label

### What We Can Do Now
- Our `codex-review.sh` already uses `codex exec --full-auto` for non-interactive mode
- Codex supports `--json` for JSONL event streams and `--output-schema` for structured output
- Codex can run as MCP server: `codex mcp-server` (runs over stdio)

### Integration Plan
1. **Update `codex-review.sh`** to use `--output-schema` for structured review output:
   ```bash
   codex exec --full-auto --json --output-schema ./config/codex-review-schema.json "Review this code..." \
     -o /tmp/codex-review-result.json
   ```
2. **Create `config/codex-review-schema.json`** defining expected output fields (findings, severity, confidence)
3. **Enable parallel sub-agent spawning** when multi-agent feature becomes GA:
   - Define agent roles in `~/.codex/config.toml`:
     ```toml
     [agents.security-reviewer]
     description = "Security vulnerability scanner"
     config_file = "agents/security.toml"
     sandbox_mode = "read-only"

     [agents.bug-detector]
     description = "Bug and logic error detection"
     config_file = "agents/bugs.toml"
     ```
   - Use `agents.max_threads` to control concurrency
   - Use `agents.max_depth = 1` (default) to prevent recursive spawning

### Key Config Knobs
| Setting | Type | Purpose |
|---------|------|---------|
| `agents.max_threads` | number | Max concurrent agent threads |
| `agents.max_depth` | number | Max nesting depth (default: 1) |

### Limitations to Plan For
- Sub-agents inherit parent sandbox; cannot escalate permissions
- Context window pollution across many files (each sub-agent has independent context)
- Cost scales linearly with sub-agent count
- Shell escaping required for `codex exec` prompts

### Sources
- [Codex Multi-agents Documentation](https://developers.openai.com/codex/multi-agent/)
- [Codex CLI Reference](https://developers.openai.com/codex/cli/reference/)
- [Codex Non-interactive Mode](https://developers.openai.com/codex/noninteractive/)
- [Codex Configuration Reference](https://developers.openai.com/codex/config-reference/)

---

## 2. OpenAI Responses API WebSocket Mode

**Status**: Available (SDK v2.22.0+)
**Priority**: Medium
**Blocked by**: Need to refactor `codex-review.sh` and debate scripts to use Python/Node SDK instead of CLI

### Current State (Feb 2026)
- WebSocket mode for Responses API released 2026-02-23 in OpenAI Python SDK v2.22.0
- Endpoint: `wss://api.openai.com/v1/responses`
- Connection limit: 60 minutes per connection
- Sequential processing only (one in-flight response per connection)

### Performance Gains
| Scenario | Improvement |
|----------|-------------|
| Tool-heavy workflows (20+ calls) | ~40% faster |
| Complex multi-file operations | ~39% faster |
| Simple tasks | ~15% faster |
| Best case | ~50% faster |

**Trade-off**: Initial WebSocket handshake adds slight TTFT overhead on short tasks.

### Integration Plan
1. **Create `scripts/openai-ws-client.py`** (or `.js`): A thin WebSocket client that:
   - Opens persistent connection to `wss://api.openai.com/v1/responses`
   - Sends `response.create` events with review prompts
   - Uses `previous_response_id` for multi-turn continuation (incremental input only)
   - Returns structured JSON findings
2. **Update debate scripts** to use WebSocket for multi-turn cross-examination:
   - Round 1: Initial review (response.create)
   - Round 2: Challenge (continue with previous_response_id + challenge input)
   - Round 3: Final position (continue with previous_response_id + final input)
   - All 3 rounds on single connection = ~40% faster debate
3. **Compatible with `store=false`** and Zero Data Retention (in-memory state only)

### Key Technical Details
- Server keeps one previous-response state in connection-local in-memory cache
- After disconnect: use `/responses/compact` endpoint for compacted context
- No multiplexing: use multiple connections for parallel runs

### Reconnection Strategies
1. Continue with `previous_response_id` (if `store=true`)
2. Start fresh with full input context
3. Use compacted output from `/responses/compact`

### Sources
- [WebSocket Mode - OpenAI Official Docs](https://developers.openai.com/api/docs/guides/websocket-mode/)
- [OpenAI Python SDK v2.22.0](https://github.com/openai/openai-python/releases)
- [Cline WebSocket Test Results](https://x.com/cline/status/2026031848791630033)
- [H2S Media: WebSocket API Performance](https://www.how2shout.com/news/openai-websocket-api-agent-latency-40-percent-faster.html)

---

## 3. Claude Code Remote Control Session Monitoring

**Status**: Research Preview (Pro/Max plans only)
**Priority**: Low
**Blocked by**: No programmatic API for Remote Control sessions; interactive-only

### Current State (Feb 2026)
- `claude remote-control` or `/remote-control` starts a remote session
- Session runs locally; web/mobile interface is a window into it
- Reconnects automatically if laptop sleeps (10-minute timeout on network loss)
- One remote session per Claude Code instance

### What Exists
- **Claude Code Analytics Admin API**: `/v1/organizations/usage_report/claude_code` for daily aggregated metrics (not per-session)
- **OpenTelemetry integration**: For general observability (not Remote Control specific)
- **No status/progress endpoint** for individual Remote Control sessions

### Integration Plan (When API Available)
1. **Pipeline progress monitoring**: If Anthropic adds a Remote Control status API, we could:
   - Start Arena pipeline via Remote Control
   - Poll progress from mobile/web
   - Receive notifications when each phase completes
2. **Multi-device review**: Start review on desktop, approve findings from mobile
3. **Background pipeline execution**: Run Arena as a Remote Control session, monitor from phone

### Current Workarounds
- Third-party projects: [Claude-Code-Remote](https://github.com/JessyTsui/Claude-Code-Remote) (email/Discord/Telegram notifications)
- Community tool: [clauderc.com](https://www.clauderc.com/) (unofficial web interface)

### Limitations
- Pro/Max plans only (not Team/Enterprise)
- API keys not supported (requires `/login` auth)
- `--dangerously-skip-permissions` not supported in Remote Control mode
- Terminal must stay open

### Sources
- [Claude Code Remote Control - Official Docs](https://code.claude.com/docs/en/remote-control)
- [Simon Willison's Coverage](https://simonwillison.net/2026/Feb/25/claude-code-remote-control/)
- [VentureBeat](https://venturebeat.com/orchestration/anthropic-just-released-a-mobile-version-of-claude-code-called-remote)

---

## 4. Gemini CLI Hooks v0.26 Cross-Compatibility

**Status**: Available (v0.26.0)
**Priority**: Medium
**Blocked by**: Need to create Gemini-compatible hook wrappers

### Current State (Feb 2026)
- Gemini CLI v0.26.0 added comprehensive hooks system with 11 event types
- Architecture very similar to Claude Code hooks but not identical
- "Should only take a few minutes to adapt an existing Claude hook to Gemini CLI"

### Gemini CLI Hook Events (11 total)
| Event | Claude Code Equivalent | Notes |
|-------|----------------------|-------|
| `SessionStart` | `PreToolUse` (partial) | Session lifecycle |
| `SessionEnd` | None | Advisory, CLI does not wait |
| `BeforeAgent` | None | After prompt, before planning |
| `AfterAgent` | None | Agent loop completes |
| `BeforeModel` | None | Before LLM request (unique to Gemini) |
| `AfterModel` | None | After LLM response (per-chunk streaming) |
| `BeforeToolSelection` | None | Filter available tools |
| `BeforeTool` | `PreToolUse` | Validate/block operations |
| `AfterTool` | `PostToolUse` | Process results |
| `PreCompress` | None | Before context compression |
| `Notification` | None | System alerts |

### Integration Plan
1. **Create `hooks/gemini-hooks.json`** mapping to Gemini's settings.json format:
   ```json
   {
     "hooks": {
       "AfterTool": [{
         "matcher": "write_file|replace",
         "hooks": [{
           "type": "command",
           "command": "$GEMINI_PROJECT_DIR/.gemini/hooks/orchestrate-review.sh",
           "timeout": 120000
         }]
       }]
     }
   }
   ```
2. **Create adapter script** `scripts/gemini-hook-adapter.sh`:
   - Translates Gemini's stdin JSON format to our expected format
   - Maps `$GEMINI_PROJECT_DIR` to `$PLUGIN_DIR`
   - Calls `orchestrate-review.sh` with adapted arguments
3. **Leverage Gemini-unique hooks**:
   - `BeforeModel`: Inject context density-filtered content before LLM request
   - `AfterModel`: Stream-level redaction of sensitive output
   - `BeforeToolSelection`: Restrict tools based on review phase

### Gemini Hook Configuration Hierarchy (4 levels)
1. Project: `.gemini/settings.json`
2. User: `~/.gemini/settings.json`
3. System: `/etc/gemini-cli/settings.json`
4. Extensions: Installed extension hooks

### Ralph Loop Pattern (Potential Adoption)
The "Ralph Loop" uses `AfterAgent` hook for autonomous multi-turn improvement:
- Agent iterates on code, clearing conversational context between turns
- Persistent state via files/git; fresh LLM context each turn
- Could be adapted for Arena's auto-fix loop (Phase 6.5)

### Sources
- [Gemini CLI Hooks Documentation](https://geminicli.com/docs/hooks/)
- [Google Developers Blog](https://developers.googleblog.com/tailor-gemini-cli-to-your-workflow-with-hooks/)
- [Ralph Extension](https://github.com/gemini-cli-extensions/ralph)
- [The New Stack: Gemini CLI Hooks](https://thenewstack.io/gemini-cli-gets-its-hooks-into-the-agentic-development-loop/)

---

## 5. Agent Marketplace / Extension Bundling Pattern

**Status**: Design Phase
**Priority**: Low
**Blocked by**: Anthropic Cowork enterprise plugin marketplace not yet public

### Concept
Package AI Review Arena as a distributable extension that other teams can install, configure, and extend.

### Design Considerations
- Gemini CLI already has extension bundling with `gemini extensions install <url> --auto-update`
- Codex has `codex mcp-server` for MCP-based integration
- Claude Code has plugin system (`.claude-plugin/`) but no public marketplace yet
- Anthropic announced "Cowork" enterprise suite with plugin ecosystem

### Integration Plan (When Platform Available)
1. **Package as installable extension** for all 3 platforms:
   - Claude Code: Already works via `.claude-plugin/plugin.json`
   - Gemini CLI: Create extension manifest with hooks
   - Codex: Create MCP server wrapper
2. **Shared configuration schema** across all platforms
3. **Auto-update mechanism** for extension updates

---

## Summary: Priority Matrix

| Item | Priority | Status | Can Start Now? |
|------|----------|--------|----------------|
| Codex `--output-schema` | High | Ready | Yes (partial) |
| Codex sub-agent roles | High | Experimental | No (wait for GA) |
| WebSocket debate acceleration | Medium | SDK available | Yes (need Python/Node client) |
| Gemini hook adapter | Medium | v0.26 available | Yes |
| Remote Control monitoring | Low | No API | No |
| Agent marketplace | Low | Design phase | No |
