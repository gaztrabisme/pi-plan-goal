---
name: plan-goal
description: Use when a Codex plan was approved, the user says "implement the plan" (or go/proceed/execute), or the UserPromptSubmit hook says the plan is approved; bridges the approved plan to a validated goal block and the user-only /goal command.
---

# Plan approved → write the goal block

The `.plan-goal/approved` flag means the user approved the plan. Before any
edit, write the goal block to `.plan-goal/goal.md`:

1. First line exactly: `Execute plan "<plan name>" (<plan file path or reference>). Goal rows:`
2. Then rows numbered consecutively from 1, one line each: `<n> <short label>: <check>`
3. Each check is a concrete command or observable test that proves the row; if
   nobody could run or observe it, it is not a check.
4. At most 4000 characters total. Optional trailing free-text lines may follow
   the rows; none may start with a digit, and no row may follow them.

Validate before you rely on it:

    codex/bin/goal-block-check .plan-goal/goal.md

Fix and rewrite until it exits 0. Then keep working the rows in order; quote
the row label when you report progress.

Never edit `.plan-goal/goal.md` after you start working the rows, except to
fix a failed validation. When you finish and Stop, the hook checks the file and
prints a `/goal …` line for the user to paste — do not try to run /goal
yourself; only the user can type it.
