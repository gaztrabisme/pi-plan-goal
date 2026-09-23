#!/bin/sh
# plan-goal PreToolUse hook.
#
# Reads the hook event JSON on stdin and uses its "cwd", "tool_name", and
# "tool_input" (Bash and apply_patch both carry the call in
# tool_input.command). While <cwd>/.plan-goal/approved exists AND
# .plan-goal/goal.md is missing or fails goal-block-check, the gate denies:
#
#   - apply_patch — Codex reports file edits as tool_name "apply_patch"
#     (the docs' Edit/Write matcher aliases are the same tool), and
#   - Bash commands that are not read-only. Read-only means every segment
#     split on newline, ;, &&, ||, and | starts with one of cat head tail
#     ls grep rg find pwd wc echo test or git status/log/diff, with no
#     redirection or tee, no command substitution ($( or backtick), no
#     find -exec/-execdir/-delete/-ok/-fprint/-fls, and no git diff
#     --output.
#
# Commands and patches that only touch .plan-goal/ are allowed, so the gate
# never gets in the way of writing and validating the goal block itself.
# Everything else — including every tool that is not Bash or apply_patch —
# exits 0 silently.
#
# Deny output (per the Codex hooks docs):
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse",
#     "permissionDecision":"deny","permissionDecisionReason":"..."}}
# Fail closed: if python3 (or the temp file) is unavailable while an
# approval is pending, exit 2 with the reason on stderr — exit code 2 with
# stderr is the docs' other blocking convention; any other failure mode
# would let the tool call through.

set -u

script_dir=$(cd "$(dirname "$0")" && pwd) || script_dir=.
PLAN_GOAL_CHECKER="${PLAN_GOAL_CHECKER:-$script_dir/../bin/goal-block-check}"
export PLAN_GOAL_CHECKER

# The hook is launched with the session cwd as its working directory, so
# ./.plan-goal/approved is the pending-approval marker the shell can see
# without Python.
fail_closed() {
	printf 'plan-goal: %s is unavailable; blocking while a plan approval is pending\n' "$1" >&2
	exit 2
}

if ! command -v python3 >/dev/null 2>&1; then
	if [ -f .plan-goal/approved ]; then
		fail_closed python3
	fi
	exit 0
fi

# The program goes through a temporary file, not "python3 -", so stdin stays
# attached to the hook event JSON.
tmp=$(mktemp "${TMPDIR:-/tmp}/plan-goal-pre.XXXXXX") || {
	if [ -f .plan-goal/approved ]; then
		fail_closed mktemp
	fi
	exit 0
}
trap 'rm -f "$tmp"' EXIT
trap 'rm -f "$tmp"; [ -f .plan-goal/approved ] && exit 2; exit 0' INT TERM

cat >"$tmp" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

script_dir = sys.argv[1]
try:
    event = json.load(sys.stdin)
except Exception:
    event = {}
if not isinstance(event, dict):
    event = {}

cwd = event.get("cwd")
if not isinstance(cwd, str) or not cwd:
    cwd = os.getcwd()
# normpath so prefix comparisons in under_plan_goal hold for cwds that
# contain redundant separators (mktemp-style ".../T//dir" sets).
cwd = os.path.normpath(cwd)
plan_dir = os.path.join(cwd, ".plan-goal")
flag_path = os.path.join(plan_dir, "approved")
goal_path = os.path.join(plan_dir, "goal.md")

if not os.path.isfile(flag_path):
    raise SystemExit(0)

checker = os.environ.get("PLAN_GOAL_CHECKER") or "goal-block-check"

if os.path.isfile(goal_path):
    try:
        run = subprocess.run(
            [checker, goal_path], stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        valid = run.returncode == 0
        problems = run.stderr.decode("utf-8", "replace").strip()
    except OSError as err:
        valid = False
        problems = "goal-block-check did not run: %s" % err
else:
    valid = False
    problems = "no goal file at " + goal_path

if valid:
    raise SystemExit(0)

tool_name = event.get("tool_name")
tool_name = tool_name if isinstance(tool_name, str) else ""
tool_input = event.get("tool_input")
if not isinstance(tool_input, dict):
    tool_input = {}
command = tool_input.get("command")
command = command if isinstance(command, str) else ""

EDIT_TOOLS = {"apply_patch", "Edit", "Write", "MultiEdit", "NotebookEdit"}
READ_ONLY_HEADS = {
    "cat", "head", "tail", "ls", "grep", "rg", "find",
    "pwd", "wc", "echo", "test",
}
GIT_READ_ONLY = {"status", "log", "diff"}
FIND_MUTATING = {"-exec", "-execdir", "-delete", "-ok", "-fprint", "-fls"}
# Heads the plan-goal branch may run: printf/echo/cat only write through a
# redirect, mkdir/touch/rm/mv/cp/tee write their arguments (which must all
# be under .plan-goal/), and goal-block-check is read-only by construction.
PLAN_GOAL_HEADS = {"printf", "echo", "cat"}
ARGUMENT_WRITERS = {"mkdir", "touch", "rm", "mv", "cp", "tee"}
PATCH_FILE = re.compile(r"^\*\*\* (?:Add|Update|Delete) File: (.+)$")
PATCH_MOVE = re.compile(r"^\*\*\* Move File: (.+?) -> (.+)$")


def under_plan_goal(path):
    full = os.path.normpath(os.path.join(cwd, path))
    return full == plan_dir or full.startswith(plan_dir + os.sep)


def segments(text):
    """Split on newline, ;, &&, ||, and | (no quote handling: fail closed)."""
    parts = []
    current = []
    index = 0
    while index < len(text):
        if text[index : index + 2] in ("&&", "||"):
            parts.append("".join(current))
            current = []
            index += 2
        elif text[index] in ";\n|":
            parts.append("".join(current))
            current = []
            index += 1
        else:
            current.append(text[index])
            index += 1
    parts.append("".join(current))
    return parts


def is_read_only(text):
    if "$(" in text or "`" in text:
        return False
    for segment in segments(text):
        words = segment.split()
        if not words:
            continue
        first = words[0]
        if first == "git":
            if len(words) < 2 or words[1] not in GIT_READ_ONLY:
                return False
            if words[1] == "diff" and any(
                word == "--output" or word.startswith("--output=")
                for word in words[2:]
            ):
                return False
        elif first == "find":
            if any(word in FIND_MUTATING for word in words[1:]):
                return False
        elif first not in READ_ONLY_HEADS:
            return False
        if ">" in segment or "tee" in words:
            return False
    return True


def plan_goal_only(text):
    """True only for commands that provably write inside .plan-goal/ and
    nowhere else (or run the read-only goal-block-check)."""
    if "$(" in text or "`" in text:
        return False
    checker_base = os.path.basename(checker)
    for segment in segments(text):
        try:
            words = shlex.split(segment)
        except ValueError:
            return False
        targets = []
        kept = []
        index = 0
        while index < len(words):
            word = words[index]
            if word in (">", ">>") and index + 1 < len(words):
                targets.append(words[index + 1])
                index += 2
            elif word.startswith(">>") and len(word) > 2:
                targets.append(word[2:])
                index += 1
            elif word.startswith(">") and len(word) > 1:
                targets.append(word[1:])
                index += 1
            else:
                kept.append(word)
                index += 1
        if any(">" in word for word in kept):
            # 2>, >&1, and friends are not understood here: fail closed.
            return False
        if kept:
            first = kept[0]
            if first in ARGUMENT_WRITERS:
                if not all(
                    under_plan_goal(word)
                    for word in kept[1:]
                    if not word.startswith("-")
                ):
                    return False
            elif (
                first not in PLAN_GOAL_HEADS
                and os.path.basename(first) != checker_base
            ):
                return False
        if not all(under_plan_goal(target) for target in targets):
            return False
    return True


def patch_paths(text):
    """Every path an apply_patch command touches, or None if the text is not
    a recognizable patch (unknown shape: fail closed)."""
    if not text or "*** Begin Patch" not in text:
        return None
    paths = []
    for line in text.split("\n"):
        move = PATCH_MOVE.match(line)
        if move is not None:
            paths.append(move.group(1).strip())
            paths.append(move.group(2).strip())
            continue
        hit = PATCH_FILE.match(line)
        if hit is not None:
            paths.append(hit.group(1).strip())
    return paths


reason = (
    "plan-goal: the approved plan has no valid goal block yet ("
    + (problems or "goal block invalid")
    + "). While that is true, only read-only commands and changes that touch "
    ".plan-goal/ are allowed. Write the goal block to .plan-goal/goal.md and "
    'validate it with "' + checker + ' .plan-goal/goal.md", then retry.'
)


def deny():
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }))
    raise SystemExit(0)


if tool_name == "Bash":
    if command and not is_read_only(command) and not plan_goal_only(command):
        deny()
elif tool_name in EDIT_TOOLS:
    paths = patch_paths(command)
    if paths is None or not all(under_plan_goal(path) for path in paths):
        deny()
raise SystemExit(0)
PY

python3 "$tmp" "$script_dir"
exit $?
