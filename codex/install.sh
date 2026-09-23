#!/bin/sh
# plan-goal installer for Codex.
#
# Copies the plan-goal package (bin/, hooks/, hooks.json, skill/) into
# $PREFIX/plan-goal (default ~/.codex/plan-goal), regenerates the installed
# hooks.json with python3 (json.dump; each command path goes through
# shlex.quote, so a PREFIX with spaces or quotes yields valid JSON and a
# launchable command), and PRINTS — does not apply — the merge instructions
# for ~/.codex/hooks.json plus the skill copy command. Codex requires
# non-managed hooks to be reviewed and trusted, so finish in the CLI with
# /hooks.
#
# Usage: install.sh [--dry-run]
#   --dry-run  print the actions without writing anything
#   PREFIX     install base directory (default "$HOME/.codex")

set -u

usage() {
	printf 'usage: install.sh [--dry-run]\n' >&2
	exit 2
}

# sh_quote STRING — print STRING quoted for the shell (POSIX single-quote
# rule), mirroring what shlex.quote produces in the installed hooks.json.
sh_quote() {
	printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

dry_run=0
for arg in "$@"; do
	case "$arg" in
	--dry-run) dry_run=1 ;;
	*) usage ;;
	esac
done

src=$(cd "$(dirname "$0")" && pwd) || exit 2
base="${PREFIX:-$HOME/.codex}"
dest="$base/plan-goal"

if [ ! -f "$src/hooks.json" ] || [ ! -x "$src/bin/goal-block-check" ]; then
	printf 'install.sh: run this from the plan-goal package directory\n' >&2
	exit 2
fi

if [ "$dry_run" -eq 0 ] && ! command -v python3 >/dev/null 2>&1; then
	printf 'install.sh: python3 is required to generate a shell-safe hooks.json\n' >&2
	exit 2
fi

if [ "$dry_run" -eq 1 ]; then
	printf 'dry run: would copy %s/{bin,hooks,hooks.json,skill} -> %s\n' "$src" "$dest"
	printf 'dry run: would generate %s/hooks.json from the template with python3 (json.dump, shlex.quote of each command path)\n' "$dest"
	printf 'dry run: would chmod +x %s/bin/goal-block-check %s/hooks/*.sh\n' "$dest" "$dest"
else
	for item in bin hooks hooks.json skill; do
		rm -rf "$dest/$item"
		mkdir -p "$dest"
		cp -R "$src/$item" "$dest/$item" || exit 2
	done
	python3 - "$dest" "$src/hooks.json" <<'PY' || exit 2
import json
import os
import shlex
import sys

dest, template = sys.argv[1], sys.argv[2]
with open(template, "r", encoding="utf-8") as handle:
    hooks = json.load(handle)
for groups in hooks.get("hooks", {}).values():
    if not isinstance(groups, list):
        continue
    for group in groups:
        if not isinstance(group, dict):
            continue
        for hook in group.get("hooks", []):
            if not isinstance(hook, dict):
                continue
            command = hook.get("command")
            if isinstance(command, str) and "__PLAN_GOAL_DIR__" in command:
                # shlex.quote keeps the command launchable when the install
                # path contains spaces or quotes; json.dump keeps the file
                # valid JSON whatever the path contains.
                hook["command"] = shlex.quote(
                    command.replace("__PLAN_GOAL_DIR__", dest)
                )
with open(os.path.join(dest, "hooks.json"), "w", encoding="utf-8") as handle:
    json.dump(hooks, handle, indent=2)
    handle.write("\n")
PY
	chmod +x "$dest/bin/goal-block-check" "$dest"/hooks/*.sh || exit 2
	printf 'installed plan-goal to %s\n' "$dest"
fi

fragment="$dest/hooks.json"
if [ "$dry_run" -eq 1 ]; then
	fragment="<dest>/hooks.json"
fi

q_pre=$(sh_quote "$dest/hooks/pre-tool-use.sh")
q_prompt=$(sh_quote "$dest/hooks/user-prompt-submit.sh")
q_stop=$(sh_quote "$dest/hooks/stop.sh")

cat <<EOF

Next steps (nothing below was applied):

1. Merge the three hook registrations below into the "hooks" object of
   $base/hooks.json (create the file if you do not have one; keep any
   hooks already there). The installed copy $fragment
   already has the real shell-quoted command paths, so merging it verbatim
   works too:

   {
     "hooks": {
       "PreToolUse": [
         {
           "matcher": "^(Bash|apply_patch|Edit|Write)\$",
           "hooks": [
             {
               "type": "command",
               "command": "$q_pre",
               "statusMessage": "Checking the plan goal before the tool runs",
               "timeout": 10
             }
           ]
         }
       ],
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "$q_prompt",
               "statusMessage": "Checking for plan approval",
               "additionalContextLimit": 4000,
               "timeout": 10
             }
           ]
         }
       ],
       "Stop": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "$q_stop",
               "statusMessage": "Checking the plan goal",
               "timeout": 30
             }
           ]
         }
       ]
     }
   }

2. Copy the skill so Codex picks up the plan-goal instructions:

   mkdir -p "$base/skills/plan-goal" && cp "$dest/skill/SKILL.md" "$base/skills/plan-goal/SKILL.md"

3. Start Codex and run /hooks to review and trust the three new hooks
   (non-managed hooks are skipped until trusted). Trust is recorded against
   the hook definition hash, so re-trust after any edit to the scripts.

EOF
exit 0
