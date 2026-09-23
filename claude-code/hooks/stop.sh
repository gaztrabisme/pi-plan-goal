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

# Stop is allowed to finish if its Python runtime is missing; otherwise an
# approved session could become stuck. Stay silent when there is no approval.
approval_root=${CLAUDE_PROJECT_DIR:-}
if [ -z "$approval_root" ]; then
    if input_cwd_from_json; then approval_root=$input_cwd; else approval_root=.; fi
fi
state_dir=$approval_root/.claude/plan-goal
if [ ! -f "$state_dir/approved" ]; then
    exit 0
fi
if ! command -v python3 >/dev/null 2>&1; then
    printf '%s\n' 'Plan-goal Stop hook: python3 is unavailable; allowing the session to stop.' >&2
    exit 0
fi

hook_dir=$(CDPATH= cd -P "$(dirname "$0")" 2>/dev/null && pwd) || exit 0
plugin_root=$(CDPATH= cd -P "$hook_dir/.." 2>/dev/null && pwd) || exit 0
checker=${PLAN_GOAL_CHECKER:-${CLAUDE_PLUGIN_ROOT:-$plugin_root}/bin/goal-block-check}
input_file=$(mktemp "${TMPDIR:-/tmp}/plan-goal-stop.XXXXXX") || exit 0
trap 'rm -f "$input_file"' EXIT HUP INT TERM
printf '%s\n' "$input_payload" >"$input_file"

python3 - "$checker" "$input_file" <<'PY'
import json
import os
import subprocess
import sys
import tempfile

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


def read_count(name):
    try:
        with open(os.path.join(state_dir, name), "r", encoding="ascii") as handle:
            return max(0, int(handle.read().strip() or "0"))
    except (OSError, ValueError):
        return 0


def write_count(name, value):
    atomic_write(os.path.join(state_dir, name), str(value) + "\n")


def checker_result():
    try:
        result = subprocess.run(
            [checker, goal], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, check=False,
        )
        return result.returncode == 0, result.stderr.strip()
    except OSError as error:
        return False, "goal-block-check: %s" % error


def extract_block(text):
    lines = text.split("\n")
    for index, line in enumerate(lines):
        if line.strip() == "## Goal block":
            end = len(lines)
            for stop in range(index + 1, len(lines)):
                if lines[stop].startswith("## "):
                    end = stop
                    break
            lines = lines[index + 1:end]
            break
    while lines and lines[0].strip() == "":
        lines.pop(0)
    while lines and lines[-1].strip() == "":
        lines.pop()
    return "\n".join(lines)


valid, problems = checker_result()
try:
    max_blocks = int(os.environ.get("PLAN_GOAL_MAX_BLOCKS", "3"))
except ValueError:
    max_blocks = 3
max_blocks = max(0, max_blocks)

if not valid:
    count = read_count("blocks")
    if count < max_blocks:
        write_count("blocks", count + 1)
        if not problems:
            problems = "goal-block-check rejected .claude/plan-goal/goal.md"
        sys.stderr.write(problems + "\n")
        sys.stderr.write(
            "Write a valid goal block to .claude/plan-goal/goal.md before stopping. "
            "Validate it with %s.\n" % checker
        )
        raise SystemExit(2)
    message = (
        "Goal is still missing or invalid after %d stop-hook blocks; write "
        ".claude/plan-goal/goal.md before stopping."
    ) % max_blocks
    print(json.dumps({"systemMessage": message}))
    raise SystemExit(0)

with open(goal, "r", encoding="utf-8") as handle:
    block = extract_block(handle.read())
active = os.path.join(state_dir, "goal.active.md")
atomic_write(active, block + "\n")

if os.environ.get("PLAN_GOAL_LOOP") == "1":
    done = os.path.join(state_dir, "done")
    if os.path.exists(done):
        try:
            os.unlink(approved)
        except FileNotFoundError:
            pass
        print(json.dumps({
            "systemMessage": "Goal loop released: .claude/plan-goal/done exists.",
        }))
        raise SystemExit(0)

    continuations = read_count("loop-count")
    if continuations < 8:
        write_count("loop-count", continuations + 1)
        print(json.dumps({
            "decision": "block",
            "reason": (
                "Goal active: keep working the rows in "
                ".claude/plan-goal/goal.active.md; when every row's check passes, "
                "write .claude/plan-goal/done with one line per row: "
                "<n> PASS <evidence>."
            ),
        }))
        raise SystemExit(0)

    try:
        os.unlink(approved)
    except FileNotFoundError:
        pass
    print(json.dumps({
        "systemMessage": (
            "Goal loop released after 8 continuations; "
            ".claude/plan-goal/done was not found."
        ),
    }))
    raise SystemExit(0)

try:
    os.unlink(approved)
except FileNotFoundError:
    pass
print(json.dumps({"systemMessage": "Paste to set the goal:\n/goal " + block}))
PY
