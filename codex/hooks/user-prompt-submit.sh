#!/bin/sh
# plan-goal UserPromptSubmit hook.
#
# Reads the hook event JSON on stdin. When the prompt looks like the user
# approving a plan (Codex plan mode has no plan-exit tool; approval is
# conversational), record the approval in <cwd>/.plan-goal/approved and tell
# the model, via additionalContext, to write the goal block to
# .plan-goal/goal.md before any edit.
#
# Output (stdout): JSON {"hookSpecificOutput":{"hookEventName":
# "UserPromptSubmit","additionalContext":"..."}} when approved, else nothing.
# Exit 0 in every case: this hook never blocks a prompt.
#
# Environment:
#   PLAN_GOAL_APPROVE_RE  approval regex, matched case-insensitively against
#                         the prompt. Default behaviour (when unset) is:
#                         ^(yes[, ]*)?(go|implement|execute|proceed)\b
#                         or the prompt containing: implement (the )?plan

set -u

script_dir=$(cd "$(dirname "$0")" && pwd) || script_dir=.
PLAN_GOAL_CHECKER="${PLAN_GOAL_CHECKER:-$script_dir/../bin/goal-block-check}"
export PLAN_GOAL_CHECKER

cat <<'PY' | python3 - "$script_dir"
import json
import os
import re
import sys

script_dir = sys.argv[1]
try:
    event = json.load(sys.stdin)
except Exception:
    event = {}
if not isinstance(event, dict):
    event = {}

prompt = event.get("prompt") or ""
cwd = event.get("cwd") or os.getcwd()

approve_re = os.environ.get("PLAN_GOAL_APPROVE_RE") or ""
if approve_re:
    approved = re.search(approve_re, prompt, re.IGNORECASE) is not None
else:
    approved = (
        re.search(r"^(yes[, ]*)?(go|implement|execute|proceed)\b", prompt, re.IGNORECASE)
        is not None
        or re.search(r"implement (the )?plan", prompt, re.IGNORECASE) is not None
    )
if not approved:
    raise SystemExit(0)

plan_dir = os.path.join(cwd, ".plan-goal")
os.makedirs(plan_dir, exist_ok=True)
with open(os.path.join(plan_dir, "approved"), "w", encoding="utf-8") as flag:
    flag.write(prompt.strip() + "\n")

checker = os.environ.get("PLAN_GOAL_CHECKER") or "goal-block-check"
context = (
    "Plan approved. Before any edit, write the goal block to "
    ".plan-goal/goal.md, validate it with \"" + checker + " .plan-goal/goal.md\""
    " (fix until it exits 0), and only then start working the rows. The block,"
    " at most 4000 characters, is:\n"
    "1. First line exactly: Execute plan \"<plan name>\" (<plan file path or"
    " reference>). Goal rows:\n"
    "2. Then one or more rows, numbered consecutively from 1, one line each:"
    " <n> <short label>: <check>\n"
    "3. Each check is a concrete command or observable test that proves the"
    " row; a check nobody could run or observe is not a check.\n"
    "4. Optional trailing free-text lines may follow the rows; none may start"
    " with a digit.\n"
    "5. No row may follow the trailing free text, and row numbers must not"
    " skip or repeat.\n"
    "6. The rows are settled at approval: write the goal file once and never"
    " edit it afterwards, except to fix a failed validation."
)
if len(context) > 4000:
    context = context[:4000]

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": context,
    }
}))
PY
exit $?
