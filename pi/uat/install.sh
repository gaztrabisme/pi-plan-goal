#!/usr/bin/env bash
# UAT: install pi-plan-goal the real way (pi install, into a fresh scratch
# PI_CODING_AGENT_DIR - never ~/.pi), alongside the two narumitw packages it
# bridges, then start pi headless once and confirm every extension loaded
# with no error.
#
# Syntax per docs/packages.md: `pi install npm:@scope/pkg@version` for npm
# sources, `pi install /absolute/path` for a local package.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

SCRATCH_BASE="$PI_DIR/.pi-scratch/install-$$-$(date +%s)"
AGENT_DIR="$SCRATCH_BASE/agentdir"
CWD="$SCRATCH_BASE/cwd"
mkdir -p "$AGENT_DIR" "$CWD"

export PI_CODING_AGENT_DIR="$AGENT_DIR"

STATUS=0

run() {
  echo "+ $*"
  "$@"
  local s=$?
  if [ "$s" -ne 0 ]; then
    echo "FAIL: command exited $s: $*"
    STATUS=1
  fi
  return $s
}

perl -e 'alarm 120; exec @ARGV' pi install npm:@narumitw/pi-plan-mode@0.58.3 </dev/null
[ $? -eq 0 ] && echo "PASS: pi install npm:@narumitw/pi-plan-mode@0.58.3" || { echo "FAIL: install pi-plan-mode"; STATUS=1; }

perl -e 'alarm 120; exec @ARGV' pi install npm:@narumitw/pi-goal@0.54.8 </dev/null
[ $? -eq 0 ] && echo "PASS: pi install npm:@narumitw/pi-goal@0.54.8" || { echo "FAIL: install pi-goal"; STATUS=1; }

perl -e 'alarm 120; exec @ARGV' pi install "$PI_DIR" </dev/null
[ $? -eq 0 ] && echo "PASS: pi install $PI_DIR" || { echo "FAIL: install pi-plan-goal by path"; STATUS=1; }

OUT="$SCRATCH_BASE/out.jsonl"
ERR="$SCRATCH_BASE/err.log"

(
  cd "$CWD" && \
  perl -e 'alarm 90; exec @ARGV' pi \
    --no-skills --no-prompt-templates --no-themes --no-context-files --no-session \
    --mode json --print --approve \
    "hi" </dev/null
) > "$OUT" 2> "$ERR"
PI_STATUS=$?

echo "--- pi stderr ---"
cat "$ERR"

if [ "$PI_STATUS" -ne 0 ]; then
  echo "FAIL: pi -p \"hi\" exited $PI_STATUS"
  STATUS=1
else
  echo "PASS: pi -p \"hi\" exited 0"
fi

if grep -qi "extension error\|failed to load extension\|could not load extension" "$ERR"; then
  echo "FAIL: extension load error in stderr"
  STATUS=1
else
  echo "PASS: no extension load error"
fi

# The session header line (first line of JSON output) proves pi actually
# started a session rather than dying before it printed anything.
if head -n1 "$OUT" | grep -q '"type":"session"'; then
  echo "PASS: session started"
else
  echo "FAIL: no session header in output"
  STATUS=1
fi

if [ "$STATUS" -eq 0 ]; then
  echo "install.sh: PASS"
else
  echo "install.sh: FAIL (agent dir: $AGENT_DIR, log: $OUT / $ERR)"
fi

exit "$STATUS"
