#!/bin/bash
# Generic logging hook: logs raw stdin plus which event/matcher fired.
EVENT="$1"
LOG="/Users/GaryT/Documents/Work/tools/pi-plan-goal/claude-code/probe-sandbox/hooks.log"
STDIN="$(cat)"
{
  echo "=== EVENT: $EVENT  TIME: $(date -u +%Y-%m-%dT%H:%M:%SZ)  PID:$$  PPID:$PPID ==="
  echo "$STDIN"
  echo
} >> "$LOG"
exit 0
