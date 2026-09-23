#!/bin/sh
set -u

hook_dir=$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
plugin_root=$(CDPATH= cd -P "$hook_dir/.." 2>/dev/null && pwd) || exit 0
checker=${PLAN_GOAL_CHECKER:-${CLAUDE_PLUGIN_ROOT:-$plugin_root}/bin/goal-block-check}
input_file=$(mktemp "${TMPDIR:-/tmp}/plan-goal-post.XXXXXX") || exit 0
trap 'rm -f "$input_file"' EXIT HUP INT TERM
cat >"$input_file"

python3 - "$checker" "$input_file" <<'PY'
import json
import os
import re
import sys
import tempfile

checker = os.path.abspath(sys.argv[1])
input_path = sys.argv[2]

try:
    with open(input_path, "r", encoding="utf-8") as handle:
        payload = json.load(handle)
except (OSError, ValueError):
    raise SystemExit(0)

cwd = payload.get("cwd") or os.getcwd()
response = payload.get("tool_response") or {}
plan = response.get("plan")
if not isinstance(plan, str):
    plan = ""
file_path = response.get("filePath")
if not isinstance(file_path, str) or not file_path:
    file_path = response.get("planFilePath") or ""
if not isinstance(file_path, str):
    file_path = ""

lines = plan.splitlines()
title = "approved plan"
for line in lines:
    match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*$", line)
    if match:
        title = match.group(1).strip()
        break
else:
    for line in lines:
        if line.strip():
            title = line.strip()
            break

title = re.sub(r"[\r\n\t]+", " ", title).strip()[:80].strip() or "approved plan"
file_path = re.sub(r"[\r\n\t]+", " ", file_path).strip()
state_dir = os.path.join(cwd, ".claude", "plan-goal")
os.makedirs(state_dir, exist_ok=True)


def atomic_write(path, text):
    fd, temp_path = tempfile.mkstemp(prefix=".plan-goal.", dir=state_dir, text=True)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temp_path, path)
    finally:
        try:
            os.unlink(temp_path)
        except FileNotFoundError:
            pass


# Archive any prior goal before arming the new approval. If both goal files
# exist, goal.md wins the single archive slot; the older archive is replaced.
previous_goal = os.path.join(state_dir, "goal.prev.md")
for name in ("goal.active.md", "goal.md"):
    path = os.path.join(state_dir, name)
    if os.path.exists(path):
        os.replace(path, previous_goal)
for name in ("blocks", "loop-count", "done"):
    try:
        os.unlink(os.path.join(state_dir, name))
    except FileNotFoundError:
        pass

atomic_write(
    os.path.join(state_dir, "approved"),
    json.dumps({"filePath": file_path, "title": title}, ensure_ascii=False) + "\n",
)

first_line = 'Execute plan "%s" (%s). Goal rows:' % (title, file_path)
context = (
    "Plan approved. Before any edit, write the goal block to "
    ".claude/plan-goal/goal.md. The first line must be exactly:\n"
    + first_line
    + "\nThen add numbered rows `<n> <label>: <check>`; every check must be "
    "a concrete command or observable check, and the block must be ≤4000 "
    "characters. Validate with "
    + checker
    + " .claude/plan-goal/goal.md, then work the rows."
)
if len(context) > 700:
    context = (
        "Plan approved. Before any edit write .claude/plan-goal/goal.md. "
        "Its first line must be exactly:\n"
        + first_line
        + "\nAdd numbered `<n> <label>: <check>` rows with concrete checks; "
        "keep the block ≤4000 characters; validate it with "
        + checker
        + " .claude/plan-goal/goal.md; then work the rows."
    )
if len(context) > 700:
    context = context[:700]

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": context,
    }
}, ensure_ascii=False))
PY
