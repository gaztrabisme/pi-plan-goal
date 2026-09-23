#!/bin/sh
# plan-goal UAT for the Codex package.
#
# Self-contained: creates its own mktemp workspace and drives the hooks with
# fixture JSON on stdin. Exits 0 only when every case passes; prints one
# PASS/FAIL line per case.
#
# Cases
#   a  UserPromptSubmit "implement the plan" -> flag + additionalContext
#      naming .plan-goal/goal.md; "what time is it" -> nothing
#   b  Stop with flag, no goal -> stdout JSON decision block, exit 0
#   c  second Stop in the same state -> no block (loop guard)
#   d  Stop with flag and a valid goal -> systemMessage has "/goal Execute
#      plan", flag removed
#   e  Stop with the 4001-char goal and a fresh counter -> block, reason
#      mentions 4001
#   f  SKILL.md has name: and description: frontmatter
#   g  codex/bin/goal-block-check is byte-identical to bin/goal-block-check
#   h  install.sh --dry-run with PREFIX into a temp dir exits 0
#   i  PreToolUse gate, approved + no/invalid goal: apply_patch outside
#      .plan-goal, `printf x > f`, and `find . -delete` denied; `ls`, a
#      patch inside .plan-goal, and a .plan-goal-only command allowed; a
#      mutating call with no approval flag allowed; missing python3 + flag
#      fails closed with exit 2
#   j  PreToolUse gate with a valid goal: the same apply_patch edit and a
#      mutating command allowed silently
#   k  install.sh with a space and a single quote in PREFIX: generated
#      hooks.json parses and the Stop command string runs via sh -c

set -u

here=$(cd "$(dirname "$0")" && pwd) || exit 2
repo=$(cd "$here/.." && pwd) || exit 2
work=$(mktemp -d "${TMPDIR:-/tmp}/plan-goal-uat.XXXXXX") || exit 2
trap 'rm -rf "$work"' EXIT

fails=0

pass() {
	printf 'PASS %s\n' "$1"
}

fail() {
	printf 'FAIL %s\n%s\n' "$1" "$2"
	fails=$((fails + 1))
}

# expect_json FILE PYTHON-EXPRESSION  — expression is evaluated with obj set
# to the parsed JSON; exit 0 when it is true.
expect_json() {
	python3 - "$1" "$2" <<'PY'
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        obj = json.load(handle)
except Exception as err:
    print("not valid JSON: %s" % err)
    raise SystemExit(1)
try:
    ok = eval(sys.argv[2], {"obj": obj})
except Exception as err:
    print("assertion error: %s" % err)
    raise SystemExit(1)
raise SystemExit(0 if ok else 1)
PY
}

# Each case runs a list of checks; a check is a command, run directly, that
# fails when the property does not hold. Description is the first argument.
errs=""
ck() {
	desc=$1
	shift
	if "$@" >/dev/null 2>&1; then
		:
	else
		errs="$errs
  - $desc"
	fi
}

case_a() {
	a_ok="$work/a-approve"
	a_no="$work/a-no"
	mkdir -p "$a_ok" "$a_no"
	printf '{"hook_event_name":"UserPromptSubmit","prompt":"implement the plan","cwd":"%s"}\n' \
		"$a_ok" >"$work/a-ok.json"
	printf '{"hook_event_name":"UserPromptSubmit","prompt":"what time is it","cwd":"%s"}\n' \
		"$a_no" >"$work/a-no.json"
	"$here/hooks/user-prompt-submit.sh" <"$work/a-ok.json" >"$work/a-ok.out"
	a_rc=$?
	"$here/hooks/user-prompt-submit.sh" <"$work/a-no.json" >"$work/a-no.out"
	a2_rc=$?

	errs=""
	ck 'approval prompt exits 0' test "$a_rc" -eq 0
	ck 'approval prompt writes the flag' test -f "$a_ok/.plan-goal/approved"
	ck 'output is UserPromptSubmit additionalContext' \
		expect_json "$work/a-ok.out" \
		'obj["hookSpecificOutput"]["hookEventName"] == "UserPromptSubmit" and ".plan-goal/goal.md" in obj["hookSpecificOutput"]["additionalContext"]'
	ck 'additionalContext is at most 4000 chars' \
		expect_json "$work/a-ok.out" \
		'len(obj["hookSpecificOutput"]["additionalContext"]) <= 4000'
	ck 'other prompt exits 0' test "$a2_rc" -eq 0
	ck 'other prompt writes nothing' test ! -e "$a_no/.plan-goal"
	ck 'other prompt prints nothing' test ! -s "$work/a-no.out"
	if [ -z "$errs" ]; then
		pass 'a UserPromptSubmit approval'
	else
		fail 'a UserPromptSubmit approval' "$errs"
	fi
}

case_bc() {
	b="$work/b-stop"
	mkdir -p "$b/.plan-goal" "$work/b-fresh/.plan-goal"
	: >"$b/.plan-goal/approved"
	: >"$work/b-fresh/.plan-goal/approved"
	printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$b" >"$work/b.json"
	printf '{"hook_event_name":"Stop","stop_hook_active":true,"cwd":"%s"}\n' \
		"$work/b-fresh" >"$work/b3.json"
	"$here/hooks/stop.sh" <"$work/b.json" >"$work/b.out"
	b_rc=$?
	"$here/hooks/stop.sh" <"$work/b.json" >"$work/b2.out"
	b2_rc=$?
	"$here/hooks/stop.sh" <"$work/b3.json" >"$work/b3.out"
	b3_rc=$?

	errs=""
	ck 'first Stop exits 0' test "$b_rc" -eq 0
	ck 'first Stop decision is block' \
		expect_json "$work/b.out" 'obj.get("decision") == "block"'
	ck 'block reason explains and names the goal file' \
		expect_json "$work/b.out" \
		'len(obj.get("reason", "")) > 40 and ".plan-goal/goal.md" in obj.get("reason", "")'
	if [ -z "$errs" ]; then
		pass 'b Stop blocks once for a missing goal'
	else
		fail 'b Stop blocks once for a missing goal' "$errs"
	fi

	errs=""
	ck 'second Stop exits 0' test "$b2_rc" -eq 0
	ck 'second Stop does not block' \
		expect_json "$work/b2.out" 'obj.get("decision") != "block"'
	ck 'second Stop says the goal is still missing' \
		expect_json "$work/b2.out" \
		'"missing" in obj.get("systemMessage", "")'
	ck 'stop_hook_active Stop does not block' \
		expect_json "$work/b3.out" 'obj.get("decision") != "block"'
	if [ -z "$errs" ]; then
		pass 'c Stop loop guard'
	else
		fail 'c Stop loop guard' "$errs"
	fi
}

case_d() {
	d="$work/d-valid"
	mkdir -p "$d/.plan-goal"
	: >"$d/.plan-goal/approved"
	cp "$repo/spec/example.md" "$d/.plan-goal/goal.md"
	printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" >"$work/d.json"
	"$here/hooks/stop.sh" <"$work/d.json" >"$work/d.out"
	d_rc=$?

	errs=""
	ck 'Stop with a valid goal exits 0' test "$d_rc" -eq 0
	ck 'systemMessage carries "/goal Execute plan"' \
		expect_json "$work/d.out" \
		'"/goal Execute plan" in obj.get("systemMessage", "")'
	ck 'valid goal does not block' \
		expect_json "$work/d.out" 'obj.get("decision") != "block"'
	ck 'flag removed' test ! -e "$d/.plan-goal/approved"
	ck 'goal file kept' test -f "$d/.plan-goal/goal.md"
	if [ -z "$errs" ]; then
		pass 'd Stop with a valid goal'
	else
		fail 'd Stop with a valid goal' "$errs"
	fi
}

case_e() {
	e="$work/e-toolong"
	mkdir -p "$e/.plan-goal"
	: >"$e/.plan-goal/approved"
	cp "$repo/spec/fixtures/too-long.md" "$e/.plan-goal/goal.md"
	printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$e" >"$work/e.json"
	"$here/hooks/stop.sh" <"$work/e.json" >"$work/e.out"
	e_rc=$?

	errs=""
	ck 'over-long goal exits 0' test "$e_rc" -eq 0
	ck 'over-long goal blocks' \
		expect_json "$work/e.out" 'obj.get("decision") == "block"'
	ck 'block reason reports 4001 chars' \
		expect_json "$work/e.out" '"4001" in obj.get("reason", "")'
	if [ -z "$errs" ]; then
		pass 'e Stop blocks on the 4001-char goal'
	else
		fail 'e Stop blocks on the 4001-char goal' "$errs"
	fi
}

case_f() {
	first=$(head -n 1 "$here/skill/SKILL.md")
	lines=$(wc -l <"$here/skill/SKILL.md")
	errs=""
	ck 'SKILL.md opens with ---' test "$first" = '---'
	ck 'SKILL.md has name: and description: frontmatter' \
		awk 'NR>1 && /^---$/{exit} /^name: plan-goal$/{n=1} /^description: .+/{d=1} END{exit !(n && d)}' \
		"$here/skill/SKILL.md"
	ck 'SKILL.md is at most 40 lines' test "$lines" -le 40
	if [ -z "$errs" ]; then
		pass 'f SKILL.md frontmatter'
	else
		fail 'f SKILL.md frontmatter' "$errs"
	fi
}

case_g() {
	errs=""
	ck 'codex checker accepts spec/example.md' \
		"$here/bin/goal-block-check" "$repo/spec/example.md"
	ck 'codex checker is byte-identical to bin/goal-block-check' \
		cmp -s "$here/bin/goal-block-check" "$repo/bin/goal-block-check"
	if [ -z "$errs" ]; then
		pass 'g goal-block-check copy'
	else
		fail 'g goal-block-check copy' "$errs"
	fi
}

case_h() {
	mkdir -p "$work/prefix"
	PREFIX="$work/prefix" "$here/install.sh" --dry-run >"$work/h.out" 2>&1
	h_rc=$?

	errs=""
	ck 'dry-run exits 0' test "$h_rc" -eq 0
	ck 'dry-run writes nothing' test ! -e "$work/prefix/plan-goal"
	ck 'dry-run prints the hooks.json merge instructions' \
		grep -q 'hooks\.json' "$work/h.out"
	if [ -z "$errs" ]; then
		pass 'h install.sh --dry-run under PREFIX'
	else
		fail 'h install.sh --dry-run under PREFIX' "$errs"
	fi
}

case_i() {
	i="$work/i-gate"
	mkdir -p "$i/.plan-goal"
	: >"$i/.plan-goal/approved"

	# apply_patch editing a file outside .plan-goal
	cat >"$work/i-patch-out.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: edited.txt\n+edited before goal\n*** End Patch"}}
EOF
	# a shell redirect outside .plan-goal
	cat >"$work/i-redirect.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"Bash","tool_input":{"command":"printf x > f"}}
EOF
	# a mutating find
	cat >"$work/i-find.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"Bash","tool_input":{"command":"find . -delete"}}
EOF
	# a read-only command
	cat >"$work/i-ls.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"Bash","tool_input":{"command":"ls"}}
EOF
	# apply_patch touching only .plan-goal/
	cat >"$work/i-patch-in.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: .plan-goal/goal.md\n+Execute plan \"x\" (p). Goal rows:\n+1 check: test -f x\n*** End Patch"}}
EOF
	# a command writing only inside .plan-goal/
	cat >"$work/i-cmd-in.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$i","tool_name":"Bash","tool_input":{"command":"printf x > .plan-goal/draft.md"}}
EOF
	# a mutating command with no approval flag in cwd
	mkdir -p "$work/i-noflag"
	cat >"$work/i-noflag.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$work/i-noflag","tool_name":"Bash","tool_input":{"command":"printf x > f"}}
EOF

	"$here/hooks/pre-tool-use.sh" <"$work/i-patch-out.json" >"$work/i-patch-out.out"
	i1=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-redirect.json" >"$work/i-redirect.out"
	i2=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-find.json" >"$work/i-find.out"
	i3=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-ls.json" >"$work/i-ls.out"
	i4=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-patch-in.json" >"$work/i-patch-in.out"
	i5=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-cmd-in.json" >"$work/i-cmd-in.out"
	i6=$?
	"$here/hooks/pre-tool-use.sh" <"$work/i-noflag.json" >"$work/i-noflag.out"
	i7=$?
	# missing python3 with a pending approval must fail closed: exit 2
	mkdir -p "$work/i-emptybin"
	i8=$(cd "$i" && PATH="$work/i-emptybin" /bin/sh "$here/hooks/pre-tool-use.sh" \
		<"$work/i-ls.json" >"$work/i-nopy.out" 2>"$work/i-nopy.err"; echo $?)

	errs=""
	ck 'apply_patch outside .plan-goal exits 0' test "$i1" -eq 0
	ck 'apply_patch outside .plan-goal is denied' \
		expect_json "$work/i-patch-out.out" \
		'obj["hookSpecificOutput"]["permissionDecision"] == "deny"'
	ck 'apply_patch deny reason names the goal file' \
		expect_json "$work/i-patch-out.out" \
		'".plan-goal/goal.md" in obj["hookSpecificOutput"]["permissionDecisionReason"] and obj["hookSpecificOutput"]["hookEventName"] == "PreToolUse"'
	ck 'redirect outside .plan-goal is denied' \
		expect_json "$work/i-redirect.out" \
		'obj["hookSpecificOutput"]["permissionDecision"] == "deny"'
	ck 'find -delete is denied' \
		expect_json "$work/i-find.out" \
		'obj["hookSpecificOutput"]["permissionDecision"] == "deny"'
	ck 'ls exits 0' test "$i4" -eq 0
	ck 'ls is allowed silently' test ! -s "$work/i-ls.out"
	ck 'apply_patch inside .plan-goal exits 0' test "$i5" -eq 0
	ck 'apply_patch inside .plan-goal is allowed silently' test ! -s "$work/i-patch-in.out"
	ck 'plan-goal-only command exits 0' test "$i6" -eq 0
	ck 'plan-goal-only command is allowed silently' test ! -s "$work/i-cmd-in.out"
	ck 'no approval flag allows everything silently' \
		sh -c 'test "$1" -eq 0 && test ! -s "$2"' sh "$i7" "$work/i-noflag.out"
	ck 'missing python3 with a flag fails closed (exit 2)' test "$i8" -eq 2
	ck 'missing python3 leaves a stderr reason' test -s "$work/i-nopy.err"
	if [ -z "$errs" ]; then
		pass 'i PreToolUse gate with no valid goal'
	else
		fail 'i PreToolUse gate with no valid goal' "$errs"
	fi
}

case_j() {
	j="$work/j-valid"
	mkdir -p "$j/.plan-goal"
	: >"$j/.plan-goal/approved"
	cp "$repo/spec/example.md" "$j/.plan-goal/goal.md"
	cat >"$work/j-patch.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$j","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Add File: edited.txt\n+edited before goal\n*** End Patch"}}
EOF
	cat >"$work/j-redirect.json" <<EOF
{"hook_event_name":"PreToolUse","cwd":"$j","tool_name":"Bash","tool_input":{"command":"printf x > f"}}
EOF
	"$here/hooks/pre-tool-use.sh" <"$work/j-patch.json" >"$work/j-patch.out"
	j1=$?
	"$here/hooks/pre-tool-use.sh" <"$work/j-redirect.json" >"$work/j-redirect.out"
	j2=$?

	errs=""
	ck 'same apply_patch edit exits 0 with a valid goal' test "$j1" -eq 0
	ck 'same apply_patch edit is allowed silently' test ! -s "$work/j-patch.out"
	ck 'mutating command is allowed silently' \
		sh -c 'test "$1" -eq 0 && test ! -s "$2"' sh "$j2" "$work/j-redirect.out"
	if [ -z "$errs" ]; then
		pass 'j PreToolUse gate with a valid goal'
	else
		fail 'j PreToolUse gate with a valid goal' "$errs"
	fi
}

case_k() {
	k="$work/k prefix's dir"
	mkdir -p "$k" "$work/k-stop-fixture/.plan-goal"
	: >"$work/k-stop-fixture/.plan-goal/approved"
	cp "$repo/spec/example.md" "$work/k-stop-fixture/.plan-goal/goal.md"
	PREFIX="$k" "$here/install.sh" >"$work/k.out" 2>&1
	k1=$?
	kj="$k/plan-goal/hooks.json"
	kcmd=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["hooks"]["Stop"][0]["hooks"][0]["command"])' "$kj" 2>/dev/null)
	printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' \
		"$work/k-stop-fixture" >"$work/k-stop.json"
	sh -c "$kcmd" <"$work/k-stop.json" >"$work/k-stop.out" 2>"$work/k-stop.err"
	k2=$?

	errs=""
	ck 'install exits 0 with a space and a quote in PREFIX' test "$k1" -eq 0
	ck 'hooks.json exists in the package destination' test -f "$kj"
	ck 'hooks.json parses' \
		expect_json "$kj" 'obj["hooks"]["Stop"][0]["hooks"][0]["command"]'
	ck 'hooks.json registers PreToolUse' \
		expect_json "$kj" '"pre-tool-use.sh" in obj["hooks"]["PreToolUse"][0]["hooks"][0]["command"]'
	ck 'Stop command string runs via sh -c' test "$k2" -eq 0
	ck 'Stop command actually ran the hook' test -s "$work/k-stop.out"
	ck 'Stop command emitted the /goal systemMessage' \
		expect_json "$work/k-stop.out" '"/goal Execute plan" in obj.get("systemMessage", "")'
	ck 'install printed the merge instructions' grep -q 'hooks\.json' "$work/k.out"
	if [ -z "$errs" ]; then
		pass 'k install.sh with spaces and quotes in PREFIX'
	else
		fail 'k install.sh with spaces and quotes in PREFIX' "$errs"
	fi
}

cd "$work" || exit 2
case_a
case_bc
case_d
case_e
case_f
case_g
case_h
case_i
case_j
case_k

printf '\n'
if [ "$fails" -eq 0 ]; then
	printf 'plan-goal UAT: all cases passed\n'
	exit 0
fi
printf 'plan-goal UAT: %d case(s) failed\n' "$fails"
exit 1
