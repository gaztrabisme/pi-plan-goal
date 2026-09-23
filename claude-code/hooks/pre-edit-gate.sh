#!/bin/sh
set -u

hook_dir=$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
plugin_root=$(CDPATH= cd -P "$hook_dir/.." 2>/dev/null && pwd) || exit 0
checker=${PLAN_GOAL_CHECKER:-${CLAUDE_PLUGIN_ROOT:-$plugin_root}/bin/goal-block-check}
input_file=$(mktemp "${TMPDIR:-/tmp}/plan-goal-pre.XXXXXX") || exit 0
trap 'rm -f "$input_file"' EXIT HUP INT TERM
cat >"$input_file"

python3 - "$checker" "$input_file" <<'PY'
import json
import os
import subprocess
import sys

checker = os.path.abspath(sys.argv[1])
try:
    with open(sys.argv[2], "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(0)

cwd = payload.get("cwd") or os.getcwd()
state_dir = os.path.join(cwd, ".claude", "plan-goal")
approved = os.path.join(state_dir, "approved")
goal = os.path.join(state_dir, "goal.md")
if not os.path.exists(approved):
    raise SystemExit(0)

tool_input = payload.get("tool_input") or {}
target = tool_input.get("file_path")
if not isinstance(target, str):
    target = ""


def absolute(path):
    if not os.path.isabs(path):
        path = os.path.join(cwd, path)
    return os.path.realpath(path)


if target and absolute(target) == absolute(goal):
    raise SystemExit(0)

valid = False
if os.path.isfile(goal):
    try:
        result = subprocess.run(
            [checker, goal], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            check=False,
        )
        valid = result.returncode == 0
    except OSError:
        valid = False
if valid:
    raise SystemExit(0)

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "permissionDecision": "deny",
        "permissionDecisionReason": (
            "Plan approved: write a valid goal block to "
            ".claude/plan-goal/goal.md before editing another file."
        ),
    }
}))
PY
