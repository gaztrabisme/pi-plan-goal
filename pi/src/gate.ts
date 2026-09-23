/**
 * The edit gate: while armed, block `edit`, `write`, and any non-read-only
 * `bash` tool call so the model has to call write_goal first.
 *
 * isMutatingBash fails closed: a bash command is read-only only if every
 * segment is recognized as one of a small set of read-only commands, with
 * no shell construct that could let a segment do more than its first word
 * suggests (redirection, substitution, or a shell/wrapper that runs
 * arbitrary further commands). Anything unparsed or unrecognized is treated
 * as mutating.
 */

const READONLY_SIMPLE = new Set(["cat", "head", "tail", "ls", "grep", "rg", "find", "pwd", "wc"]);

// Split on every shell statement separator the spec calls out, plus literal
// newlines - a command string can smuggle a second statement on its own
// line without using any of ; && || |, so a newline has to be treated the
// same as a `;`. Longest alternatives first so "||" and "&&" aren't cut
// into single "|"/"&" pieces.
const SEGMENT_SPLIT = /\|\||&&|;|\||\r?\n/;

// find options that mutate the filesystem or run further commands. Checked
// as exact tokens against find's argument list.
const FIND_MUTATING_OPTIONS = new Set([
  "-exec",
  "-execdir",
  "-delete",
  "-ok",
  "-okdir",
  "-fprint",
  "-fprint0",
  "-fprintf",
  "-fls",
]);

// git flags that write files or run external programs (diff can shell out
// via --ext-diff/--textconv, or write with --output), or that change what
// git itself runs (-c, --exec-path). Checked against every argument after
// the subcommand, not just the ones a well-formed invocation would put
// there, so a flag in an unexpected position still gets caught.
const GIT_DISALLOWED_FLAGS = ["-c", "--exec-path", "--output", "--ext-diff", "--textconv"];

function isReadonlyFind(args: string[]): boolean {
  return !args.some((arg) => FIND_MUTATING_OPTIONS.has(arg));
}

function isReadonlyGit(args: string[]): boolean {
  const [sub, ...rest] = args;
  if (sub !== "status" && sub !== "log" && sub !== "diff") return false;
  return !rest.some((arg) =>
    GIT_DISALLOWED_FLAGS.some((flag) => arg === flag || arg.startsWith(`${flag}=`)),
  );
}

function isReadonlySegment(segment: string): boolean {
  const tokens = segment.trim().split(/\s+/).filter(Boolean);
  if (tokens.length === 0) return true; // no-op segment (e.g. blank line, trailing ";"): nothing to run
  const [cmd, ...rest] = tokens;
  if (cmd === "find") return isReadonlyFind(rest);
  if (cmd === "git") return isReadonlyGit(rest);
  // Everything else, including shells/interpreters/wrappers that can run
  // arbitrary further commands (env, xargs, sh, bash, nohup, sudo, tee, ...),
  // is rejected unless it's in the plain read-only allowlist.
  return READONLY_SIMPLE.has(cmd);
}

/** True when the bash command is anything other than the read-only allowlist. */
export function isMutatingBash(command: string): boolean {
  // These constructs can make a segment do more than its first word
  // suggests, so they're rejected wherever they appear in the command,
  // regardless of segment boundaries.
  if (command.includes(">")) return true; // redirection: >, >>, <>, and >(process substitution)
  if (command.includes("<(")) return true; // process substitution
  if (command.includes("$(")) return true; // command substitution
  if (command.includes("`")) return true; // command substitution (backticks)

  const segments = command.split(SEGMENT_SPLIT);
  if (segments.every((segment) => segment.trim().length === 0)) return true; // empty/no command: fail closed
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
