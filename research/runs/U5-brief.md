# U5 — adversarial review of the plan→goal bridges

Read-only on code: write only research/review.md. You may create scratch files under /tmp and run any test or hook script. Do not git commit. Write the report even if you run out of time.

## Target
Three packages chain "plan approved" to "agent must write a goal block ≤4000 chars" (format: spec/goal-block.md, validator bin/goal-block-check):
- pi/ — pi extension (src/index.ts, gate.ts, goal-block.ts, signal.ts; tests in pi/test, UAT pi/uat/*.sh). Seam facts: pi/probe.md. Decisions D11, D12 in wiki/decisions.md.
- claude-code/ — Claude Code plugin (hooks/*.sh, hooks/hooks.json, .claude-plugin/). Seam facts: claude-code/probe.md.
- codex/ — Codex hooks + skill (hooks/*.sh, hooks.json, skill/SKILL.md, install.sh).
All three UATs pass today: `cd pi && npm test && bash uat/headless.sh && bash uat/install.sh`, `bash claude-code/uat.sh`, `bash codex/uat.sh`.

## Change
Try to break them. Prove each finding with a concrete reproduction you actually ran (command + observed output), not a reading. Priority targets:
1. Gate bypass: can the agent edit files while armed and before a valid goal? (pi bash allowlist evasion: find -exec/-delete, git checkout/apply, sed -i via allowed binaries, env/xargs, quoting, newlines, tee; Claude Code tools not in the matcher such as Bash `>`, MultiEdit/NotebookEdit coverage; pi tools other than edit/write.)
2. Cap evasion or mis-count: multi-byte, CRLF, trailing whitespace, the "## Goal block" extraction path, a block that passes the TS port but fails bin/goal-block-check or vice versa.
3. Loops: can any Stop hook or the pi bridge loop forever or deadlock (stop_hook_active handling, counters never reset, loop mode cap, a goal that can never validate).
4. State: resume/new session mid-plan (pi "Start fresh", session switch), stale flags from an old plan blocking a new session, concurrent sessions in one cwd, cwd with spaces or quotes, missing python3.
5. Injection/safety: plan title or goal text with shell metacharacters, JSON escaping in hook output, path traversal via filePath.
6. Install scripts: anything destructive, clobbering existing ~/.codex/hooks.json or settings.

## Acceptance
research/review.md with a table: ID | Severity (HIGH = gate bypass, infinite loop, data loss, or a UAT claim that is false; MED; LOW) | Package | Finding | Repro (exact command) | Observed | Suggested fix (one or two lines). Then a short section per HIGH with the full repro. End with a line `HIGH count: N`. Report the file path and HIGH count.
