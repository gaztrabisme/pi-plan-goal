#!/usr/bin/env bash
set -u -o pipefail

root=$(CDPATH= cd -P "$(dirname "$0")/.." && pwd)
post="$root/claude-code/hooks/post-exit-plan.sh"
pre="$root/claude-code/hooks/pre-edit-gate.sh"
stop="$root/claude-code/hooks/stop.sh"
checker="$root/claude-code/bin/goal-block-check"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/plan-goal-uat.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
unset PLAN_GOAL_MAX_BLOCKS PLAN_GOAL_LOOP PLAN_GOAL_CHECKER
failures=0

pass_case() { echo "PASS $1"; }
fail_case() { echo "FAIL $1"; failures=1; }

post_fixture() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
out, cwd, path = sys.argv[1:]
json.dump({
    "session_id": "bd427112-d7bc-4dbd-bbfa-5db92afb8d99",
    "transcript_path": "/Users/GaryT/.claude/projects/.../session.jsonl",
    "cwd": cwd, "scratchpad_dir": "/private/tmp/claude-501/session/scratchpad",
    "prompt_id": "0fcd569a-165d-4cda-be17-5d0a35cc10a8",
    "permission_mode": "acceptEdits", "hook_event_name": "PostToolUse",
    "tool_name": "ExitPlanMode", "tool_input": {},
    "tool_response": {"plan": "# Ship the fixture\n\nCreate the requested file.",
                     "isAgent": False, "filePath": path, "hasTaskTool": True},
    "tool_use_id": "toolu_01WyzXQbDcHdJj1NzF1ekfzK", "duration_ms": 2
}, open(out, "w", encoding="utf-8"))
PY
}

pre_fixture() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
out, cwd, path = sys.argv[1:]
json.dump({
    "session_id": "pre-session",
    "transcript_path": "/Users/GaryT/.claude/projects/.../pre.jsonl",
    "cwd": cwd, "prompt_id": "pre-prompt", "permission_mode": "acceptEdits",
    "hook_event_name": "PreToolUse", "tool_name": "Write",
    "tool_input": {"file_path": path, "content": "fixture"}
}, open(out, "w", encoding="utf-8"))
PY
}

bash_fixture() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
out, cwd, command = sys.argv[1:]
json.dump({
    "cwd": cwd, "permission_mode": "acceptEdits",
    "hook_event_name": "PreToolUse", "tool_name": "Bash",
    "tool_input": {"command": command}
}, open(out, "w", encoding="utf-8"))
PY
}

stop_fixture() {
    python3 - "$1" "$2" "$3" <<'PY'
import json, sys
out, cwd, active = sys.argv[1:]
json.dump({
    "session_id": "483f27dd-ce71-4955-8cad-c458a1215a47",
    "transcript_path": "/Users/GaryT/.claude/projects/.../stop.jsonl",
    "cwd": cwd, "scratchpad_dir": "/private/tmp/claude-501/session/scratchpad",
    "prompt_id": "8dedd0b7-5ffa-4bac-89e8-3d25d219e4b5",
    "permission_mode": "default", "hook_event_name": "Stop",
    "stop_hook_active": active == "true",
    "last_assistant_message": "Hi—what are we building today?",
    "background_tasks": [], "session_crons": []
}, open(out, "w", encoding="utf-8"))
PY
}

approved() {
    mkdir -p "$1/.claude/plan-goal"
    printf '%s\n' '{"filePath":"/Users/GaryT/.claude/plans/fixture.md","title":"Ship the fixture"}' \
        >"$1/.claude/plan-goal/approved"
}

stop_4001_expected() {
    local cwd=$1 override=${2:-} rc
    approved "$cwd"
    cp "$root/spec/fixtures/too-long.md" "$cwd/.claude/plan-goal/goal.md"
    stop_fixture "$cwd/input.json" "$cwd" false
    if [ -n "$override" ]; then
        PLAN_GOAL_CHECKER="$override" "$stop" <"$cwd/input.json" >"$cwd/out" 2>"$cwd/err"
        rc=$?
    else
        "$stop" <"$cwd/input.json" >"$cwd/out" 2>"$cwd/err"
        rc=$?
    fi
    [ "$rc" -eq 2 ] && grep -q 4001 "$cwd/err"
}

# a: PostToolUse approval state and context.
a="$tmp/a"; mkdir -p "$a"
path="/Users/GaryT/.claude/plans/fixture.md"
post_fixture "$a/input.json" "$a" "$path"
"$post" <"$a/input.json" >"$a/out" 2>"$a/err"; rc=$?
if [ "$rc" -eq 0 ] && python3 - "$a/out" "$a" "$path" <<'PY'
import json, os, sys
out, cwd, path = sys.argv[1:]
result = json.load(open(out, encoding="utf-8"))
context = result["hookSpecificOutput"]["additionalContext"]
saved = json.load(open(os.path.join(cwd, ".claude/plan-goal/approved"), encoding="utf-8"))
assert ".claude/plan-goal/goal.md" in context and path in context and len(context) <= 700
assert saved == {"filePath": path, "title": "Ship the fixture"}
PY
then pass_case "a PostToolUse approval"; else fail_case "a PostToolUse approval"; fi

# b: deny another file, allow the goal file.
b="$tmp/b"; mkdir -p "$b"; post_fixture "$b/input.json" "$b" "$path"
"$post" <"$b/input.json" >"$b/post.out" 2>"$b/post.err"
pre_fixture "$b/src.json" "$b" "src/x.py"
pre_fixture "$b/goal.json" "$b" ".claude/plan-goal/goal.md"
"$pre" <"$b/src.json" >"$b/src.out" 2>"$b/src.err"; src_rc=$?
"$pre" <"$b/goal.json" >"$b/goal.out" 2>"$b/goal.err"; goal_rc=$?
if [ "$src_rc" -eq 0 ] && [ "$goal_rc" -eq 0 ] && python3 - "$b/src.out" <<'PY'
import json, sys
result = json.load(open(sys.argv[1], encoding="utf-8"))
assert result["hookSpecificOutput"]["permissionDecision"] == "deny"
assert ".claude/plan-goal/goal.md" in result["hookSpecificOutput"]["permissionDecisionReason"]
PY
then
    if [ ! -s "$b/goal.out" ]; then pass_case "b PreToolUse edit gate"; else fail_case "b PreToolUse edit gate"; fi
else
    fail_case "b PreToolUse edit gate"
fi

# c: oversized goal returns exit 2 and checker diagnostics.
c="$tmp/c"; mkdir -p "$c"
if stop_4001_expected "$c"; then pass_case "c oversized goal blocks"; else fail_case "c oversized goal blocks"; fi

# d: valid goal becomes active and prints the pasteable command.
d="$tmp/d"; mkdir -p "$d"; approved "$d"
cp "$root/spec/example.md" "$d/.claude/plan-goal/goal.md"
stop_fixture "$d/input.json" "$d" false
"$stop" <"$d/input.json" >"$d/out" 2>"$d/err"; rc=$?
if [ "$rc" -eq 0 ] && python3 - "$d/out" "$d" <<'PY'
import json, os, sys
out, cwd = sys.argv[1:]
result = json.load(open(out, encoding="utf-8"))
assert "/goal Execute plan" in result["systemMessage"]
assert not os.path.exists(os.path.join(cwd, ".claude/plan-goal/approved"))
assert os.path.isfile(os.path.join(cwd, ".claude/plan-goal/goal.active.md"))
PY
then pass_case "d valid goal paste"; else fail_case "d valid goal paste"; fi

# e: three missing-goal blocks, then a capped system message.
e="$tmp/e"; mkdir -p "$e"; approved "$e"; stop_fixture "$e/input.json" "$e" false
ok=1
for n in 1 2 3; do
    "$stop" <"$e/input.json" >"$e/out.$n" 2>"$e/err.$n"; [ "$?" -eq 2 ] || ok=0
done
"$stop" <"$e/input.json" >"$e/out.4" 2>"$e/err.4"; rc=$?
if [ "$rc" -eq 0 ] && [ "$ok" -eq 1 ] && python3 - "$e/out.4" <<'PY'
import json, sys
assert "still missing" in json.load(open(sys.argv[1], encoding="utf-8"))["systemMessage"]
PY
then pass_case "e default Stop cap"; else fail_case "e default Stop cap"; fi

# f: loop mode blocks eight times, releases on the ninth, and honors done.
f="$tmp/f"; mkdir -p "$f"; approved "$f"
cp "$root/spec/example.md" "$f/.claude/plan-goal/goal.md"
stop_fixture "$f/false.json" "$f" false
stop_fixture "$f/true.json" "$f" true
ok=1
for n in 1 2 3 4 5 6 7 8; do
    input="$f/true.json"; [ "$n" -eq 1 ] && input="$f/false.json"
    PLAN_GOAL_LOOP=1 "$stop" <"$input" >"$f/out.$n" 2>"$f/err.$n"; rc=$?
    [ "$rc" -eq 0 ] || ok=0
    python3 - "$f/out.$n" <<'PY' || ok=0
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8")).get("decision") == "block"
PY
done
PLAN_GOAL_LOOP=1 "$stop" <"$f/true.json" >"$f/out.9" 2>"$f/err.9"; rc=$?
[ "$rc" -eq 0 ] || ok=0
python3 - "$f/out.9" <<'PY' || ok=0
import json, sys
assert "8 continuations" in json.load(open(sys.argv[1], encoding="utf-8"))["systemMessage"]
PY
fd="$tmp/f-done"; mkdir -p "$fd"; approved "$fd"
cp "$root/spec/example.md" "$fd/.claude/plan-goal/goal.md"
printf '%s\n' '1 PASS fixture evidence' >"$fd/.claude/plan-goal/done"
stop_fixture "$fd/input.json" "$fd" true
PLAN_GOAL_LOOP=1 "$stop" <"$fd/input.json" >"$fd/out" 2>"$fd/err"; rc=$?
[ "$rc" -eq 0 ] || ok=0
python3 - "$fd/out" <<'PY' || ok=0
import json, sys
assert "done exists" in json.load(open(sys.argv[1], encoding="utf-8"))["systemMessage"]
PY
if [ "$ok" -eq 1 ]; then pass_case "f loop cap and done"; else fail_case "f loop cap and done"; fi

# g: no approval is silent.
g="$tmp/g"; mkdir -p "$g"; stop_fixture "$g/input.json" "$g" false
"$stop" <"$g/input.json" >"$g/out" 2>"$g/err"; rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$g/out" ] && [ ! -s "$g/err" ]; then pass_case "g unapproved Stop"; else fail_case "g unapproved Stop"; fi

# h: checker is byte-identical.
if cmp -s "$root/claude-code/bin/goal-block-check" "$root/bin/goal-block-check"; then pass_case "h checker copy"; else fail_case "h checker copy"; fi

# i: manifests parse and all configured command paths exist.
if python3 - "$root/claude-code/.claude-plugin/plugin.json" "$root/claude-code/.claude-plugin/marketplace.json" "$root/claude-code/hooks/hooks.json" "$root/claude-code" <<'PY'
import json, os, sys
plugin_path, marketplace_path, hooks_path, root = sys.argv[1:]
plugin = json.load(open(plugin_path, encoding="utf-8"))
marketplace = json.load(open(marketplace_path, encoding="utf-8"))
hooks = json.load(open(hooks_path, encoding="utf-8"))
assert plugin["name"] == "plan-goal"
assert marketplace["plugins"][0]["name"] == "plan-goal"
assert marketplace["plugins"][0]["source"] == "./"
commands = [handler["command"] for groups in hooks["hooks"].values() for group in groups for handler in group["hooks"]]
assert len(commands) == 3
marker = chr(36) + "{CLAUDE_PLUGIN_ROOT}/"
for command in commands:
    assert command.startswith(marker)
    assert os.path.isfile(os.path.join(root, command[len(marker):]))
PY
then pass_case "i plugin schemas and scripts"; else fail_case "i plugin schemas and scripts"; fi

# j: a checker stub that always succeeds makes c fail; the UAT must notice.
j="$tmp/j"; mkdir -p "$j"; stub="$j/checker-stub"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$stub"; chmod +x "$stub"
if stop_4001_expected "$j" "$stub"; then fail_case "j broken-copy self-test"; else pass_case "j broken-copy self-test"; fi

# k: Bash is gated before a valid goal; allow simple reads and the two narrow
# plan-goal operations (checker invocation and a literal goal-file here-doc).
k="$tmp/k"; mkdir -p "$k"; approved "$k"
printf '%s\n' 'not a goal block' >"$k/.claude/plan-goal/goal.md"
bash_fixture "$k/redir.json" "$k" 'printf x > edited.txt'
bash_fixture "$k/read.json" "$k" 'ls -la .'
bash_fixture "$k/find.json" "$k" 'find . -delete'
bash_fixture "$k/diff.json" "$k" 'git diff --output=edited.diff'
bash_fixture "$k/checker.json" "$k" "$checker .claude/plan-goal/goal.md"
bash_fixture "$k/heredoc.json" "$k" "cat > .claude/plan-goal/goal.md <<'EOF'
Execute plan \"fixture\" (fixture.md). Goal rows:
1 check: test -f fixture
EOF"
bash_fixture "$k/trailing.json" "$k" "cat > .claude/plan-goal/goal.md <<'EOF'
fixture
EOF
rm -f edited.txt"
ok=1
for name in redir find diff trailing; do
    (cd "$k" && "$pre" <"$k/$name.json" >"$k/$name.out" 2>"$k/$name.err"); rc=$?
    [ "$rc" -eq 0 ] || ok=0
    python3 - "$k/$name.out" <<'PY' || ok=0
import json, sys
assert json.load(open(sys.argv[1], encoding="utf-8"))["hookSpecificOutput"]["permissionDecision"] == "deny"
PY
done
(cd "$k" && "$pre" <"$k/read.json" >"$k/read.out" 2>"$k/read.err"); read_rc=$?
(cd "$k" && "$pre" <"$k/checker.json" >"$k/checker.out" 2>"$k/checker.err"); checker_rc=$?
(cd "$k" && "$pre" <"$k/heredoc.json" >"$k/heredoc.out" 2>"$k/heredoc.err"); heredoc_rc=$?
if [ "$ok" -eq 1 ] && [ "$read_rc" -eq 0 ] && [ "$checker_rc" -eq 0 ] && [ "$heredoc_rc" -eq 0 ] \
    && [ ! -s "$k/read.out" ] && [ ! -s "$k/read.err" ] \
    && [ ! -s "$k/checker.out" ] && [ ! -s "$k/checker.err" ] \
    && [ ! -s "$k/heredoc.out" ] && [ ! -s "$k/heredoc.err" ]; then
    pass_case "k Bash read-only and goal-file gate"
else
    fail_case "k Bash read-only and goal-file gate"
fi

# l: without Python, an approved PreToolUse fails closed; an unapproved one
# stays silent. Stop deliberately fails open with a diagnostic to avoid wedging.
l="$tmp/l"; mkdir -p "$l/approved" "$l/unapproved" "$l/bin"
approved "$l/approved"
pre_fixture "$l/approved/input.json" "$l/approved" "src/new.py"
pre_fixture "$l/unapproved/input.json" "$l/unapproved" "src/new.py"
stop_fixture "$l/approved/stop.json" "$l/approved" false
stop_fixture "$l/unapproved/stop.json" "$l/unapproved" false
CLAUDE_PROJECT_DIR= PATH="$l/bin" /bin/sh "$pre" <"$l/approved/input.json" >"$l/approved/out" 2>"$l/approved/err"; approved_rc=$?
CLAUDE_PROJECT_DIR= PATH="$l/bin" /bin/sh "$pre" <"$l/unapproved/input.json" >"$l/unapproved/out" 2>"$l/unapproved/err"; unapproved_rc=$?
CLAUDE_PROJECT_DIR= PATH="$l/bin" /bin/sh "$stop" <"$l/approved/stop.json" >"$l/approved/stop.out" 2>"$l/approved/stop.err"; stop_rc=$?
CLAUDE_PROJECT_DIR= PATH="$l/bin" /bin/sh "$stop" <"$l/unapproved/stop.json" >"$l/unapproved/stop.out" 2>"$l/unapproved/stop.err"; stop_unapproved_rc=$?
if [ "$approved_rc" -eq 2 ] && [ -s "$l/approved/err" ] && [ ! -s "$l/approved/out" ] \
    && [ "$unapproved_rc" -eq 0 ] && [ ! -s "$l/unapproved/out" ] && [ ! -s "$l/unapproved/err" ] \
    && [ "$stop_rc" -eq 0 ] && [ -s "$l/approved/stop.err" ] && [ ! -s "$l/approved/stop.out" ] \
    && [ "$stop_unapproved_rc" -eq 0 ] && [ ! -s "$l/unapproved/stop.err" ] && [ ! -s "$l/unapproved/stop.out" ]; then
    pass_case "l missing Python behavior"
else
    fail_case "l missing Python behavior"
fi

# m: each new approval archives the prior goal and resets all plan-local state.
m="$tmp/m"; mkdir -p "$m/.claude/plan-goal"
cp "$root/spec/example.md" "$m/.claude/plan-goal/goal.md"
printf '%s\n' 'old active goal' >"$m/.claude/plan-goal/goal.active.md"
printf '%s\n' 'older archive' >"$m/.claude/plan-goal/goal.prev.md"
printf '%s\n' '1' >"$m/.claude/plan-goal/blocks"
printf '%s\n' '7' >"$m/.claude/plan-goal/loop-count"
printf '%s\n' '1 PASS stale evidence' >"$m/.claude/plan-goal/done"
post_fixture "$m/input.json" "$m" "$path"
(cd "$m" && "$post" <input.json >out 2>err); post_rc=$?
post_state_ok=0
if [ "$post_rc" -eq 0 ] && python3 - "$m/.claude/plan-goal" <<'PY'
import os, sys
state = sys.argv[1]
assert os.path.isfile(os.path.join(state, "approved"))
assert not os.path.exists(os.path.join(state, "goal.md"))
assert not os.path.exists(os.path.join(state, "goal.active.md"))
assert open(os.path.join(state, "goal.prev.md"), encoding="utf-8").read().startswith("Execute plan ")
assert not any(os.path.exists(os.path.join(state, name)) for name in ("blocks", "loop-count", "done"))
PY
then post_state_ok=1; fi
pre_fixture "$m/src.json" "$m" "src/new.py"
(cd "$m" && "$pre" <src.json >src.out 2>src.err); deny_rc=$?
cp "$root/spec/example.md" "$m/.claude/plan-goal/goal.md"
(cd "$m" && "$pre" <src.json >src-after.out 2>src-after.err); allow_rc=$?
if [ "$post_state_ok" -eq 1 ] && [ "$deny_rc" -eq 0 ] && [ "$allow_rc" -eq 0 ] \
    && python3 - "$m/.claude/plan-goal" "$m/src.out" "$m/src-after.out" <<'PY'
import json, os, sys
state, denied, allowed = sys.argv[1:]
assert os.path.isfile(os.path.join(state, "goal.md"))
assert json.load(open(denied, encoding="utf-8"))["hookSpecificOutput"]["permissionDecision"] == "deny"
assert not open(allowed, encoding="utf-8").read().strip()
PY
then pass_case "m new approval clears stale goal"; else fail_case "m new approval clears stale goal"; fi

exit "$failures"
