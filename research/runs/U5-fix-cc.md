# Fix review findings H2, H3, H4 in claude-code/

Write only under claude-code/ (not probe-sandbox/). Do not git commit. Read research/review.md for the full findings and repros; read claude-code/probe.md for measured hook behavior.

## Target
- H2: Bash is outside the PreToolUse matcher, so `printf x > file` edits while approved and before a valid goal.
- H3: without python3 on PATH the PreToolUse gate exits 127 with no output, which fails open.
- H4: a valid goal.md left from an earlier plan satisfies the gate after a new approval.

## Change
- H2: add Bash to the PreToolUse matcher. While approved and no valid goal, deny any Bash command that is not read-only. Read-only = every segment (split on newlines, ;, &&, ||, |) starts with an allowlisted command (cat head tail ls grep rg find git-status git-log git-diff pwd wc echo test) with no redirection (> >> tee), no command substitution, and for find no -exec/-execdir/-delete/-ok/-fprint*/-fls; git diff without --output. Allow commands that only touch .claude/plan-goal/ (e.g. running the checker on goal.md, cat > .claude/plan-goal/goal.md via heredoc) — keep this narrow and document it.
- H3: when the approved file exists and python3 is missing, the gate must fail closed: exit 2 with a stderr reason, using only POSIX sh to test for the approved file. When not approved, stay silent. Stop hook behavior without python3: exit 0 with a stderr note (fail open on Stop to avoid a stuck session) — document it.
- H4: post-exit-plan.sh moves any existing goal.md and goal.active.md to goal.prev.md (overwriting) on every new approval, and resets done/counters.
Add UAT cases proving each: (k) Bash redirection denied while approved/no goal, read-only Bash allowed, `find . -delete` denied, heredoc to .claude/plan-goal/goal.md allowed; (l) PATH without python3 + approved → exit 2; not approved → exit 0 silent; (m) old valid goal.md + new approval → Write to src denied until a new goal is written. All existing cases must stay PASS.

## Acceptance
`bash claude-code/uat.sh` exits 0 with every case PASS including k, l, m; `claude plugin validate claude-code` passes. Report files changed and the uat output.
