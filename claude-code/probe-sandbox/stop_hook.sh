#!/bin/bash
# Stop hook: logs raw stdin, then on first firing per VARIANT tries to block
# stopping using one of two output conventions. Second firing (after the
# model's next turn) lets it stop, so the session terminates.
LOG="/Users/GaryT/Documents/Work/tools/pi-plan-goal/claude-code/probe-sandbox/hooks.log"
STDIN="$(cat)"
VARIANT="${STOP_VARIANT:-A}"
SANDBOX="/Users/GaryT/Documents/Work/tools/pi-plan-goal/claude-code/probe-sandbox"
STATE="$SANDBOX/stop_state_${VARIANT}.txt"

{
  echo "=== EVENT: Stop  VARIANT:$VARIANT  TIME: $(date -u +%Y-%m-%dT%H:%M:%SZ)  PID:$$  PPID:$PPID ==="
  echo "$STDIN"
} >> "$LOG"

if [ ! -f "$STATE" ]; then
  touch "$STATE"
  if [ "$VARIANT" = "A" ]; then
    echo "  -> BLOCKING via exit 2 + stderr" >> "$LOG"
    echo "BLOCK: write probe-sandbox/goal.txt before stopping (variant A, exit 2 stderr)" >&2
    exit 2
  else
    echo "  -> BLOCKING via exit 0 + stdout JSON decision:block" >> "$LOG"
    echo '{"decision":"block","reason":"BLOCK: write probe-sandbox/goal.txt before stopping (variant B, stdout JSON)"}'
    exit 0
  fi
else
  echo "  -> second firing, letting it stop (state file exists)" >> "$LOG"
  exit 0
fi
