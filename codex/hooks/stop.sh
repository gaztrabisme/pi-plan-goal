#!/bin/sh
# plan-goal Stop hook.
#
# Reads the Stop event JSON on stdin and uses its "cwd". Codex plan mode has
# no plan-exit tool, so approval is recorded by the UserPromptSubmit hook in
# <cwd>/.plan-goal/approved; this hook turns that approval into a validated
# goal block the user can paste into the user-only /goal command.
#
#   no flag file            -> exit 0, no output
#   flag + missing/invalid
#   .plan-goal/goal.md      -> block once: {"decision":"block","reason":...}
#                              (reason = goal-block-check stderr + instruction)
#   loop guard              -> stop_hook_active true, or .plan-goal/blocks has
#                              reached PLAN_GOAL_MAX_BLOCKS (default 1): exit 0
#                              with a systemMessage saying the goal is missing
#   flag + valid goal.md    -> remove the flag; exit 0 with a systemMessage
#                              "Paste to set the goal:\n/goal " + header + rows
#
# Codex Stop takes JSON on stdout when it exits 0 (plain text is invalid for
# this event); "decision":"block" continues the turn with "reason" as the new
# prompt, and "systemMessage" is surfaced to the user.

set -u

script_dir=$(cd "$(dirname "$0")" && pwd) || script_dir=.
PLAN_GOAL_CHECKER="${PLAN_GOAL_CHECKER:-$script_dir/../bin/goal-block-check}"
export PLAN_GOAL_CHECKER

# The program goes through a temporary file, not "python3 -", so stdin stays
# attached to the hook event JSON.
tmp=$(mktemp "${TMPDIR:-/tmp}/plan-goal-stop.XXXXXX") || exit 0
trap 'rm -f "$tmp"' EXIT
trap 'rm -f "$tmp"; exit 0' INT TERM

cat >"$tmp" <<'PY'
import json
import os
import subprocess
import sys

script_dir = sys.argv[1]
try:
    event = json.load(sys.stdin)
except Exception:
    event = {}
if not isinstance(event, dict):
    event = {}

cwd = event.get("cwd") or os.getcwd()
stop_hook_active = bool(event.get("stop_hook_active"))
try:
    max_blocks = int(os.environ.get("PLAN_GOAL_MAX_BLOCKS") or "1")
except ValueError:
    max_blocks = 1
if max_blocks < 0:
    max_blocks = 0

plan_dir = os.path.join(cwd, ".plan-goal")
flag_path = os.path.join(plan_dir, "approved")
goal_path = os.path.join(plan_dir, "goal.md")
counter_path = os.path.join(plan_dir, "blocks")

if not os.path.isfile(flag_path):
    raise SystemExit(0)

checker = os.environ.get("PLAN_GOAL_CHECKER") or "goal-block-check"


def goal_block_text(path):
    """Header plus numbered rows, dropping blank lines and trailing text."""
    try:
        with open(path, "r", encoding="utf-8") as handle:
            lines = handle.read().split("\n")
    except OSError:
        return None
    while lines and not lines[0].strip():
        lines.pop(0)
    if not lines:
        return None
    keep = [lines[0]]
    for line in lines[1:]:
        stripped = line.strip()
        if not stripped:
            continue
        if stripped[0].isdigit():
            keep.append(line)
        else:
            break
    return "\n".join(keep)


def read_counter():
    try:
        with open(counter_path, "r", encoding="utf-8") as handle:
            return int(handle.read().strip() or "0")
    except (OSError, ValueError):
        return 0


def emit(payload):
    print(json.dumps(payload))


if os.path.isfile(goal_path):
    run = subprocess.run(
        [checker, goal_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    valid = run.returncode == 0
    problems = run.stderr.decode("utf-8", "replace").strip()
else:
    valid = False
    problems = "no goal file at " + goal_path

if valid:
    for path in (flag_path, counter_path):
        try:
            os.remove(path)
        except OSError:
            pass
    block = goal_block_text(goal_path) or ""
    emit({"systemMessage": "Paste to set the goal:\n/goal " + block})
    raise SystemExit(0)

blocked = read_counter()
if stop_hook_active or blocked >= max_blocks:
    emit({
        "systemMessage": (
            "plan-goal: the goal block at .plan-goal/goal.md is still missing "
            "or invalid (not blocking again after %d of %d allowed). Fix or "
            "write the file, or paste /goal yourself." % (blocked, max_blocks)
        )
    })
    raise SystemExit(0)

try:
    with open(counter_path, "w", encoding="utf-8") as handle:
        handle.write("%d\n" % (blocked + 1))
except OSError:
    pass

reason = (
    (problems or "goal block invalid")
    + "\nBefore any edit, write a valid goal block to .plan-goal/goal.md: "
    'first line Execute plan "<plan name>" (<plan file path or reference>). '
    "Goal rows: then rows \"<n> <label>: <check>\" numbered from 1, at most "
    "4000 characters; validate with \"" + checker + " .plan-goal/goal.md\", "
    "then stop again."
)
emit({"decision": "block", "reason": reason})
raise SystemExit(0)
PY

python3 "$tmp" "$script_dir"
exit $?
