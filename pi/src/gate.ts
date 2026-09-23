/**
 * The edit gate: while armed, block `edit`, `write`, and any non-read-only
 * `bash` tool call so the model has to call write_goal first.
 */

const READONLY_SIMPLE = new Set(["cat", "head", "tail", "ls", "grep", "rg", "find", "pwd", "wc"]);
// Split on the shell operators the spec calls out. Longest alternatives first
// so "||" and "&&" aren't cut into single "|"/"&" pieces.
const SEGMENT_SPLIT = /\|\||&&|;|\|/;

function isReadonlySegment(segment: string): boolean {
  const tokens = segment.trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return false;
  const [cmd, sub] = tokens;
  if (READONLY_SIMPLE.has(cmd)) return true;
  if (cmd === "git") return sub === "status" || sub === "log" || sub === "diff";
  return false;
}

/** True when the bash command is anything other than the read-only allowlist. */
export function isMutatingBash(command: string): boolean {
  if (command.includes(">")) return true; // redirection: never allowed, even split across segments
  if (command.includes("$(")) return true; // command substitution: can't statically verify
  const segments = command.split(SEGMENT_SPLIT);
  if (segments.length === 0) return true;
  return segments.some((segment) => !isReadonlySegment(segment));
}

export const GATED_TOOL_NAMES = new Set(["edit", "write"]);

export interface GateDecision {
  block: boolean;
  reason?: string;
}

const BLOCK_REASON =
  'Plan approved and armed: call write_goal with the goal block for this plan before any edit or write. See spec/goal-block.md.';

/** Decide whether a tool call should be blocked while the bridge is armed. */
export function gateToolCall(toolName: string, input: unknown): GateDecision {
  if (GATED_TOOL_NAMES.has(toolName)) {
    return { block: true, reason: BLOCK_REASON };
  }
  if (toolName === "bash") {
    const command = (input as { command?: unknown } | undefined)?.command;
    if (typeof command === "string" && isMutatingBash(command)) {
      return { block: true, reason: BLOCK_REASON };
    }
  }
  return { block: false };
}
