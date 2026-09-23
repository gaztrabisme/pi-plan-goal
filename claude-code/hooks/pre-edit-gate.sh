#!/bin/sh
set -u

input_payload=
input_line=
while IFS= read -r input_line || [ -n "$input_line" ]; do
    if [ -n "$input_payload" ]; then
        input_payload="$input_payload
$input_line"
    else
        input_payload=$input_line
    fi
done

input_cwd=
input_cwd_from_json() {
    input_rest=${input_payload#*'"cwd"'}
    [ "$input_rest" != "$input_payload" ] || return 1
    case "$input_rest" in *:*) input_rest=${input_rest#*:} ;; *) return 1 ;; esac
    while [ -n "$input_rest" ]; do
        case "$input_rest" in
            [[:space:]]*) input_rest=${input_rest#?} ;;
            *) break ;;
        esac
    done
    case "$input_rest" in
        \"*) input_rest=${input_rest#\"} ;;
        *) return 1 ;;
    esac
    input_cwd=${input_rest%%\"*}
    case "$input_cwd" in *'\'*) return 1 ;; esac
    [ -n "$input_cwd" ]
}

# Hooks run in the project working directory. Check approval with shell builtins
# before invoking Python so an unapproved session stays silent and a missing
# Python runtime cannot silently bypass an active gate.
approval_root=${CLAUDE_PROJECT_DIR:-}
if [ -z "$approval_root" ]; then
    if input_cwd_from_json; then approval_root=$input_cwd; else approval_root=.; fi
fi
state_dir=$approval_root/.claude/plan-goal
if [ ! -f "$state_dir/approved" ]; then
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Plan-goal PreToolUse gate: python3 is required while a plan is approved.' >&2
    exit 2
fi

hook_dir=$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
plugin_root=$(CDPATH= cd -P "$hook_dir/.." 2>/dev/null && pwd) || exit 0
checker=${PLAN_GOAL_CHECKER:-${CLAUDE_PLUGIN_ROOT:-$plugin_root}/bin/goal-block-check}
input_file=$(mktemp "${TMPDIR:-/tmp}/plan-goal-pre.XXXXXX") || exit 0
trap 'rm -f "$input_file"' EXIT HUP INT TERM
printf '%s\n' "$input_payload" >"$input_file"

python3 - "$checker" "$input_file" <<'PY'
import json
import os
import re
import shlex
import subprocess
import sys

checker = os.path.realpath(os.path.abspath(sys.argv[1]))
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
tool_name = payload.get("tool_name")
command = tool_input.get("command")
if not isinstance(command, str):
    command = ""


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


def goal_heredoc(text):
    # Only a literal, single-quoted here-doc to the exact goal path is exempt.
    first_line, separator, body = text.partition("\n")
    pattern = (
        r"[ \t]*cat[ \t]+>[ \t]*(?:'\.claude/plan-goal/goal\.md'|"
        r'"\.claude/plan-goal/goal\.md"|\.claude/plan-goal/goal\.md)'
        r"[ \t]+<<'([A-Za-z_][A-Za-z0-9_]*)'[ \t]*\r?"
    )
    header = re.fullmatch(pattern, first_line)
    if not separator or header is None:
        return False
    lines = body.splitlines()
    if not lines:
        return False
    delimiter = header.group(1)
    # Bash consumes the first matching delimiter; require it to be the final
    # line so nothing after the here-doc can run as another command.
    return lines[-1] == delimiter and delimiter not in lines[:-1]


def run_goal_checker(text):
    try:
        words = shlex.split(text, posix=True)
    except ValueError:
        return False
    if len(words) != 2:
        return False
    executable, argument = words
    executable_path = executable if os.path.isabs(executable) else os.path.join(cwd, executable)
    if os.path.realpath(executable_path) != checker:
        return False
    return absolute(argument) == absolute(goal)


def read_only_bash(text):
    # Reject shell features that can execute nested commands or write files.
    if any(marker in text for marker in ("$(", "`", "<(", ">(", ">")):
        return False
    # Splitting conservatively may reject quoted punctuation, but cannot hide a
    # later command after a shell list or pipeline operator.
    segments = re.split(r"\r?\n|&&|\|\||[;|&]", text)
    if not segments or any(not segment.strip() for segment in segments):
        return False
    allowed = {"cat", "head", "tail", "ls", "grep", "rg", "find", "pwd", "wc", "echo", "test",
               "git-status", "git-log", "git-diff"}
    for segment in segments:
        try:
            words = shlex.split(segment, posix=True)
        except ValueError:
            return False
        if not words:
            return False
        name = os.path.basename(words[0])
        args = words[1:]
        if name == "git":
            if not args or args[0] not in ("status", "log", "diff"):
                return False
            subcommand = args.pop(0)
            name = "git-" + subcommand
        if name not in allowed:
            return False
        if name == "find" and any(
            arg in ("-exec", "-execdir", "-delete", "-ok") or
            arg.startswith(("-fprint", "-fls"))
            for arg in args
        ):
            return False
        if name == "git-diff" and any(arg == "--output" or arg.startswith("--output=") for arg in args):
            return False
    return True


if tool_name == "Bash" and (goal_heredoc(command) or run_goal_checker(command) or read_only_bash(command)):
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
