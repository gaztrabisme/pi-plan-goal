#!/usr/bin/env bash
# Deterministic headless UAT for pi-plan-goal.
#
# Loads the real, published @narumitw/pi-goal (via `pi -e npm:...`, so this
# does not depend on any local clone or build) plus this bridge's src and a
# scripted provider (uat/scripted-provider.ts) that drives a fixed script:
#   1. a harmless warm-up turn ("go")
#   2. the extension injects the plan-mode implementation handoff text
#   3. (a) edit -> blocked (armed gate)
#      (b) write_goal(too-long fixture) -> error mentioning 4001
#      (c) write_goal(example.md) -> ok, dispatches /goal
#      (d) write -> succeeds (disarmed)
#
# Runs in a scratch PI_CODING_AGENT_DIR and cwd under pi/.pi-scratch/ (never
# touches ~/.pi). Exits 0 only if every assertion in check-headless.mjs
# passes.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROOT="$(cd "$PI_DIR/.." && pwd)"

SCRATCH_BASE="$PI_DIR/.pi-scratch/headless-$$-$(date +%s)"
AGENT_DIR="$SCRATCH_BASE/agentdir"
CWD="$SCRATCH_BASE/cwd"
mkdir -p "$AGENT_DIR" "$CWD"

export PLAN_GOAL_TOO_LONG_FIXTURE="$ROOT/spec/fixtures/too-long.md"
export PLAN_GOAL_EXAMPLE_FIXTURE="$ROOT/spec/example.md"

OUT="$SCRATCH_BASE/out.jsonl"
ERR="$SCRATCH_BASE/err.log"

(
  cd "$CWD" && \
  PI_CODING_AGENT_DIR="$AGENT_DIR" \
  perl -e 'alarm 240; exec @ARGV' pi \
    -e npm:@narumitw/pi-goal@0.54.8 \
    -e "$PI_DIR/src/index.ts" \
    -e "$SCRIPT_DIR/scripted-provider.ts" \
    --no-skills --no-prompt-templates --no-themes --no-context-files --no-session \
    --provider scripted --model scripted-1 \
    --mode json --print --approve \
    "go" </dev/null
) > "$OUT" 2> "$ERR"
PI_STATUS=$?

echo "--- pi stderr ---"
cat "$ERR"
echo "--- assertions ---"
node "$SCRIPT_DIR/check-headless.mjs" "$OUT" "$CWD" "$PI_STATUS"
CHECK_STATUS=$?

if [ "$CHECK_STATUS" -eq 0 ]; then
  echo "headless.sh: PASS"
else
  echo "headless.sh: FAIL (see above; event log: $OUT, cwd: $CWD)"
fi

exit "$CHECK_STATUS"
