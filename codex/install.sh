#!/bin/sh
# plan-goal installer for Codex.
#
# Copies the plan-goal package (bin/, hooks/, hooks.json, skill/) into
# $PREFIX/plan-goal (default ~/.codex/plan-goal), rewrites the
# __PLAN_GOAL_DIR__ placeholder in the installed hooks.json, and PRINTS —
# does not apply — the merge instructions for ~/.codex/hooks.json plus the
# skill copy command. Codex requires non-managed hooks to be reviewed and
# trusted, so finish in the CLI with /hooks.
#
# Usage: install.sh [--dry-run]
#   --dry-run  print the actions without writing anything
#   PREFIX     install base directory (default "$HOME/.codex")

set -u

usage() {
	printf 'usage: install.sh [--dry-run]\n' >&2
	exit 2
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

if [ "$dry_run" -eq 1 ]; then
	printf 'dry run: would copy %s/{bin,hooks,hooks.json,skill} -> %s\n' "$src" "$dest"
	printf 'dry run: would rewrite __PLAN_GOAL_DIR__ -> %s in %s/hooks.json\n' "$dest" "$dest"
	printf 'dry run: would chmod +x %s/bin/goal-block-check %s/hooks/*.sh\n' "$dest" "$dest"
else
	for item in bin hooks hooks.json skill; do
		rm -rf "$dest/$item"
		mkdir -p "$dest"
		cp -R "$src/$item" "$dest/$item" || exit 2
	done
	sed "s|__PLAN_GOAL_DIR__|$dest|g" "$dest/hooks.json" >"$dest/hooks.json.new" &&
		mv "$dest/hooks.json.new" "$dest/hooks.json" || exit 2
	chmod +x "$dest/bin/goal-block-check" "$dest"/hooks/*.sh || exit 2
	printf 'installed plan-goal to %s\n' "$dest"
fi

fragment="$dest/hooks.json"
if [ "$dry_run" -eq 1 ]; then
	fragment="<dest>/hooks.json"
fi

cat <<EOF

Next steps (nothing below was applied):

1. Merge the two hook registrations below into the "hooks" object of
   $base/hooks.json (create the file if you do not have one; keep any
   hooks already there). The installed copy $fragment
   already has the real absolute paths, so merging it verbatim works too:

   {
     "hooks": {
       "UserPromptSubmit": [
         {
           "hooks": [
             {
               "type": "command",
               "command": "$dest/hooks/user-prompt-submit.sh",
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
               "command": "$dest/hooks/stop.sh",
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

3. Start Codex and run /hooks to review and trust the two new hooks
   (non-managed hooks are skipped until trusted). Trust is recorded against
   the hook definition hash, so re-trust after any edit to the scripts.

EOF
exit 0
