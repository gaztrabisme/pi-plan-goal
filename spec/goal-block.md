# Goal block — format spec

Reader: an AI agent that must write a goal block once its plan is approved.
Canonical instance: the "## Goal block" section of
wiki/goals/2026-09-22-plan-goal.md (the text between that heading and
"## Working pattern", trimmed). Validator: `bin/goal-block-check [FILE]`
(stdin when FILE is absent or "-"); exit 0 valid, 1 invalid with one problem
per stderr line, 2 usage error.

## Rules

a. The whole block is at most 4000 characters (Unicode characters, not bytes).
b. The first line is exactly of the form:

   Execute plan "<plan name>" (<plan file path or reference>). Goal rows:

   with a non-empty plan name inside the double quotes and a non-empty file
   path or reference inside the parentheses.
c. Then one or more rows, numbered consecutively from 1, one line each:

   <n> <short label>: <check>

   where the check is a concrete command or observable test that proves the
   row. A check that no one could run or observe is not a check.
d. Optional trailing free-text lines after the rows; none may start with a
   digit, and no row may follow them.

## Example

Execute plan "Tidy the lockers" (plans/lockers.md). Goal rows:
1 probe: test -f lockers/README.md
2 swap: grep -c 'locker 4' lockers/manifest.txt outputs 1
3 report: test -s reports/lockers.md

Rows are settled when the plan is approved; the block is written to the goal
file and not edited after dispatch.

## What the validator rejects

- too long: 4001/4000 characters
- missing header line (first line not of the rule-b form, or block empty)
- row 2: missing check after ':' (nothing observable after the colon)
- rows not consecutive: expected 3 got 4 (numbering gap or duplicate)
- row 1: expected "<n> <label>: <check>" (row line without a colon)
- no goal rows; free text before row 1; row after trailing free text
