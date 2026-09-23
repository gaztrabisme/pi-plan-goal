# Plan to Goal for Claude Code

After an approved plan, PreToolUse denies edits until
`.claude/plan-goal/goal.md` contains a valid goal block. The Bash matcher applies
the same gate to shell commands.

While the goal is missing or invalid, Bash allows only commands whose every
segment is a read-only allowlisted command: `cat`, `head`, `tail`, `ls`, `grep`,
`rg`, `find`, `git status`, `git log`, `git diff`, `pwd`, `wc`, `echo`, and
`test`. Segments are separated by newlines, `;`, `&&`, `||`, pipes, and `&`.
Redirection, command substitution, `tee`, `find` execution/deletion options,
and `git diff --output` are denied.

The only shell write exception is a single-quoted heredoc written by `cat` to
the exact path `.claude/plan-goal/goal.md`. The gate also allows invoking this
plugin's `goal-block-check` on that exact file. These exceptions let the user
set and validate the approved goal without opening a general shell write path.

PreToolUse checks for approval with POSIX shell before starting Python. If
Python is unavailable, an approved session receives exit 2 and a stderr reason;
an unapproved session remains silent. Stop uses a deliberate fail-open policy:
if an approved session lacks Python, it exits 0 with a stderr note so a runtime
dependency cannot leave the session stuck. An unapproved Stop remains silent.

Every new approval moves any existing `goal.active.md` and `goal.md` into
`goal.prev.md` (replacing an older archive), then clears the `done`, `blocks`,
and `loop-count` state before creating the new approval marker. If both goal
files exist, `goal.md` is the final content in the single archive slot.
