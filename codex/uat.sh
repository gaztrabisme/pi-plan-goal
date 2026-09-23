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

cd "$work" || exit 2
case_a
case_bc
case_d
case_e
case_f
case_g
case_h

printf '\n'
if [ "$fails" -eq 0 ]; then
	printf 'plan-goal UAT: all cases passed\n'
	exit 0
fi
printf 'plan-goal UAT: %d case(s) failed\n' "$fails"
exit 1
