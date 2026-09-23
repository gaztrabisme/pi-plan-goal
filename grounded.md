# Grounded — 2026-09-22 — plan→goal chain

CERIC hunt over every input to the plan. One section per input. MISSING = the input should supply it and does not.

## 1. Gary's brief (the /conductor argument)

- **Claim.** A pi extension that, after the user approves a plan, forces the agent to write a goal block under 4,000 chars and hands it to a goal tool; reuse existing plan and goal packages (token-efficient, maintained); the same chain for Claude Code, Codex "and other"; GLM and DeepSeek lanes are usable.
- **Evidence.** None given; it is an intent.
- **Reasoning.** Implied: a plan without a stop condition lets the agent stop early; a stop condition without a plan lets it wander. 4,000 chars matches `/goal`'s cap in Claude Code and in `@narumitw/pi-goal`.
- **Context.** Gary's conductor skill already prescribes exactly this sequence (Plan Block → goal file → session stop) by hand; this project automates the seam.
- **Implications.** Deliverable is a small bridge per harness, not a new plan or goal implementation.
- **MISSING.** Which "pi": the TypeScript pi (installed, v0.87.0) or pi_agent_rust (efficient-pi, 0.3.0). Whether "trigger the goal tool" means the agent activates the goal itself or the user does. Which "other" harnesses. Whether the goal block content is prescribed (conductor's criteria table) or free.

## 2. Local machine state (read this session)

- **Claim.** pi installed is `@earendil-works/pi-coding-agent` 0.87.0 (`~/.pi/agent`, packages: `npm:pi-mcp-adapter`, extensions copied from Amos Blomqvist's pi-config). It ships `examples/extensions/plan-mode/` (390 lines, approval = `ctx.ui.select` on `agent_end`, exec branch at index.ts:296) and `todo.ts`. Claude Code 2.1.278. Codex CLI 0.153.4 with `~/.codex/hooks.json` already carrying SessionStart/UserPromptSubmit/PreToolUse/PermissionRequest/PostToolUse/Stop entries (nodeterm), so `features.hooks` is on.
- **Evidence.** `pi --version`, `package.json`, `ls`, `cat` of the files above.
- **Reasoning.** The Codex variant has a config home already; the pi bundled example is the no-dependency baseline to compare against.
- **Context.** efficient-pi (pi_agent_rust) is a separate harness with a QuickJS extension API and no goal primitive found; its `submit_plan` tool exists.
- **Implications.** Build for the TS pi. Note pi_agent_rust as a follow-up.
- **Lane state.** `~/.claude.json` points the `subagent` MCP at `~/Documents/Work/tools/agent-capabilities/bin/subagent-mcp`, which does not exist. `~/.local/bin/subagent-mcp` (uv tool) starts cleanly but sees no API keys because nothing sources `~/.config/agent-capabilities/subagent.env`. So GLM and DeepSeek are down this session by a missing 5-line wrapper, not by quota. Codex lane: last recorded closed 2026-09-15 (per-account credit limit); status today untested. Claude Agent tool: open.
- **MISSING.** Whether Codex has credit today.

## 3. pi ecosystem survey (agent report, sources: local docs, github.com/earendil-works/pi, pi.dev/packages, npm)

- **Claim.** Plan mode candidates: bundled `plan-mode` (official, no tools, text-parse approval, ~700 B/turn while active); `@narumitw/pi-plan-mode` 0.58.3 (monorepo 601 stars, pushed 2026-09-21, tools `plan_mode_question`/`plan_mode_complete`, TUI menu Implement/Save/Export/Revise, 4.8 KB ≈1.2k tokens while active, fail-closed edit gate); `@janvitos/pi-plan-build` (7.7 KB prompts, heaviest); `@plannotator/pi-extension` (browser UI, exposes `pi.events` channel); `@agimon-ai/doompi-plan` (alpha). Goal candidates: `@narumitw/pi-goal` 0.54.8 (same monorepo, `MAX_OBJECTIVE_LENGTH = 4_000`, `agent_settled` continuation, 1.7 KB ≈430 tokens, tools `goal_complete`/`goal_blocked`/`goal_wait`, goal set by `/goal` command); `pi-codex-goal` 0.3.0 (192 stars, pushed 2026-09-22, model-callable `create_goal`, 8,000 cap, ≈300 tokens); `pi-goal` Michaelliv (stale since 2026-06); `pi-goal-x`, `pi-supervisor` (heavier).
- **Evidence.** Package versions, star counts, push dates, byte counts of prompt literals, quoted source constants.
- **Reasoning.** The narumitw pair is the only maintained plan+goal set from one author, and its goal cap already equals Gary's 4,000. pi-codex-goal is the only one where the model creates the goal by tool call.
- **Context.** `@mariozechner/pi-coding-agent` is deprecated; imports are `@earendil-works/*`. Space is crowded (30+ packages).
- **Implications.** Bridge = a third, small extension. Two ways to activate the goal from the bridge: dispatch `/goal <block>` via `pi.sendUserMessage(..., { expandPromptTemplates: true })` (documented to dispatch extension commands), or wrap `pi-codex-goal`'s `create_goal`.
- **API facts (0.87.0, quoted).** `tool_result` fires after execution and may patch the result; `pi.sendMessage` with `deliverAs: "steer"|"followUp"` and `triggerTurn`; `turn_end` / `agent_before_settle` return `{ entries, continue }` (doc-preferred continuation; unconditional `continue: true` loops); `agent_settled` is notification-only; `tool_call` returns `{ block, reason }` and `event.input` is mutable; throwing in `execute` sets `isError` so the model sees the message; TypeBox `Type.String({ maxLength: 4000 })` for schema-level caps. No public cross-extension tool invocation; `pi.events` is the shared bus.
- **MISSING.** The exact signal `@narumitw/pi-plan-mode` emits when the user picks "Implement here" (a `pi.events` emit, a custom session entry, or nothing). Whether `sendUserMessage("/goal …", { expandPromptTemplates: true })` reaches another package's command in practice. Token cost of plannotator and doompi.

## 4. Claude Code hooks and /goal (agent report, sources: code.claude.com/docs hooks, goal, tools-reference)

- **Claim.** `/goal` is a user slash command, 4,000-char cap, session-scoped, judged each turn by a small model; the model cannot invoke it, and no hook output can execute a slash command. `ExitPlanMode` is a tool, so `PostToolUse` matcher `"ExitPlanMode"` fires; `PermissionDenied` does not fire on a user's plan rejection. `additionalContext` (≤8,000 chars) from PostToolUse and Stop is model-visible. Stop hook blocks via exit code 2 (docs no longer show a `decision: "block"` field or `stop_hook_active`). `UserPromptExpansion` can only block. Hooks ship in settings.json or a plugin's `hooks/hooks.json`; hook types `command|http|mcp_tool|prompt|agent`.
- **Evidence.** Doc pages cited; schemas quoted.
- **Reasoning.** The chain on Claude Code cannot end in the native `/goal` without one user keystroke. Either the bridge prints the `/goal` line for the user to paste, or it runs its own stop loop from a goal file.
- **Context.** Gary's conductor already keeps a goal file with a UAT column; a self-run Stop loop is the harness-map's "goal file's UAT column is the stop" case.
- **Implications.** Claude Code variant = PostToolUse(ExitPlanMode) → force a goal file ≤4,000 chars; Stop hook validates it and prints the `/goal` line; optional self-loop bounded by a counter.
- **MISSING.** Whether PostToolUse fires on a rejected ExitPlanMode and what `tool_response` carries; the current Stop-hook JSON block field and loop-guard field. Both are settled by a local dump-stdin probe (unit U0b).

## 5. Other harnesses (agent report, sources: OpenAI cookbook and learn.chatgpt.com docs, geminicli.com, opencode.ai, docs.github.com, cursor.com, oh-my-pi repo, pi_agent_rust repo)

- **Claim.** Codex: native `/plan` (collaboration modes) and native `/goal` (`[features] goals`, default on since v0.133, model tools `get_goal`/`update_goal`), hooks with `additionalContext` and Stop `decision: "block"`, plugin packaging; no plan-exit tool, approval is conversational; `update_plan` tool opt-in since v0.152. Gemini: `exit_plan_mode` tool, `AfterTool` and `AfterAgent` deny-loop, ralph extension as prior art, `gemini extensions install`. Copilot: plan mode, `agentStop` block (max 8), plugin install. Cursor: `/plan`, `stop` hook `followup_message`. opencode: plan agent, no approval, no blocking stop hook. Oh My Pi: native `/plan` with Plan Review and native `/goal set`, mutually exclusive modes. pi_agent_rust: `submit_plan`, goal MISSING.
- **Evidence.** URLs per row; version numbers where stated.
- **Reasoning.** Codex needs glue only (skill + Stop hook). Gemini is the next-cheapest full chain (tool to match, loop primitive, prior art). The rest need a plan-approval heuristic.
- **Context.** Only Codex and Oh My Pi have both primitives natively.
- **Implications.** This run: pi, Claude Code, Codex. Gemini documented as the next unit, not built.
- **MISSING.** Codex `/goal` under `codex exec`; Cursor CLI approval mechanics; pi_agent_rust stop-time event.

Grounded: brief · ~/.pi/agent · pi 0.87.0 docs/extensions.md and examples/plan-mode · ~/.codex/hooks.json · ~/.claude.json mcpServers · three agent reports → build for TS pi on the narumitw pair with a bridge extension; Claude Code chain ends in a printed `/goal` line or a bounded self-loop; Codex chain is skill plus Stop hook onto native `/goal`; GLM/DeepSeek lane needs a wrapper before it can take units.
