# Decisions — 2026-09-22 Plan Block

| # | Decision | Chosen | Rejected |
|---|---|---|---|
| D1 | Which pi | TypeScript pi 0.87.0 (`@earendil-works/pi-coding-agent`) | pi_agent_rust / efficient-pi: no goal primitive, different API; follow-up |
| D2 | Plan package | `@narumitw/pi-plan-mode` (tool-based approval, fail-closed edit gate, workflow mutex with pi-goal) | bundled plan-mode example (regex over prose); `@janvitos/pi-plan-build` (~1.9k tokens); plannotator (browser UI) |
| D3 | Goal package | `@narumitw/pi-goal` (4,000 cap, goal_blocked/goal_wait/goal_complete, 25-turn guard) | `pi-codex-goal` (8,000 cap, ~130 tokens cheaper; fallback); Michaelliv pi-goal (stale); pi-goal-x, pi-supervisor (heavier) |
| D4 | Who writes the goal | The agent, via `write_goal`, with edits blocked until it does | Bridge pre-fills from the plan |
| D5 | Goal block shape | Gary's format: header line naming plan + file, then numbered rows each with a check; validated by `bin/goal-block-check` | Free text |
| D6 | Claude Code ending | Stop hook prints the `/goal` line for the user to paste; opt-in self-loop `PLAN_GOAL_LOOP=1` capped at 8 | Hook-driven `/goal` (impossible: hooks cannot run slash commands) |
| D7 | Scope of "other" | Build pi, Claude Code, Codex; document Gemini, Copilot, Cursor, opencode, Oh My Pi | Building all seven |
| D8 | Lane repair | Wrapper at agent-capabilities/bin/subagent-mcp sourcing subagent.env (done 2026-09-22, verified) | Upgrading to the TOML build |
| D9 | Codex credit | Try Spark first, reroute on first refusal | — |
| D10 | Packaging | `git init`, commit per wave, no remote | Pushing to GitHub |
| D11 | write_goal schema cap (U1, forced by measurement) | TypeBox maxLength 16000 as a ceiling; the 4000 rule enforced in execute() so the model sees "too long: 4001/4000 characters" | maxLength 4000 in schema: pi rejects before execute() with a generic message |
| D12 | When the pi bridge arms (U1, forced by measurement) | input handler returns a transform appending the write_goal instruction; arm entry written at next turn_start | sendMessage/appendEntry inside the input handler: crashes turn_end ("could not resolve the persisted assistant entry ID") |
| D13 | Review H7: codex reinstall replaces files inside ~/.codex/plan-goal/ | REJECTED as a defect: that directory is owned by the installer and replaced wholesale on upgrade; user hooks in ~/.codex/hooks.json are untouched (the finding itself observed PREFIX/hooks.json survived). README install note covers it. | Staged merge that preserves unknown files in the package dir |
| D14 | Review HIGH findings (research/review.md) | H1 fixed in 381f342 (pi bash gate fails closed). H2, H3, H4 fixed in 364a507 (Claude Code Bash gate, fail closed without python3, stale goal cleared on new approval). H5, H6 fixed in f54c31e (Codex PreToolUse gate, shell-quoted install paths). H7 rejected, see D13. | — |
| D15 | Codex model for U5 | gpt-6-luna after `codex update` to 0.156.1 (Gary) | gpt-5.6-luna (used for U2 only, already running) |
