# plan-goal

A small bridge that chains "plan approved" to "the agent must work against a
written goal". You enter plan mode, the agent writes a plan, you approve it.
After approval the bridge forces the agent to produce a goal block, a short
numbered list of tasks each with a concrete check, capped at 4000 characters.
The cap exists because that is the `/goal` limit on Claude Code and on
`@narumitw/pi-goal`, so a block that size can always be handed to a goal
tracker in one piece. On pi the chain is automatic: the bridge
(`pi/src/index.ts`) detects the plan-mode handoff, gates all edit tools until
the agent calls `write_goal`, and then starts the goal itself by dispatching
`/goal <block>` to `@narumitw/pi-goal`. On Claude Code and on Codex no hook
can type `/goal` for you; only the user can. There the Stop hook validates the
goal file and prints a `/goal ...` line that you paste to start goal
tracking.

## Goal block format

Spec: [spec/goal-block.md](spec/goal-block.md). Validator:
[bin/goal-block-check](bin/goal-block-check) (also copied into each harness
package). The block is at most 4000 characters. First line, exactly:

    Execute plan "<plan name>" (<plan file path or reference>). Goal rows:

Then numbered rows, consecutive from 1, each `<n> <short label>: <check>`
where the check is a command or observable test nobody can fake. Example:

    Execute plan "Tidy the lockers" (plans/lockers.md). Goal rows:
    1 probe: test -f lockers/README.md
    2 swap: grep -c 'locker 4' lockers/manifest.txt outputs 1
    3 report: test -s reports/lockers.md

Run `bin/goal-block-check [FILE]` (stdin if no file): exit 0 valid, 1
invalid with one problem per stderr line, 2 usage error.

## Install

### pi

Three `pi install` commands (this is what `pi/uat/install.sh` runs; use
absolute paths, and set `PI_CODING_AGENT_DIR` if you want a scratch home
rather than `~/.pi`):

    pi install npm:@narumitw/pi-plan-mode@0.58.3
    pi install npm:@narumitw/pi-goal@0.54.8
    pi install /absolute/path/to/this-repo/pi

Start `pi` as usual. Plan with the plan-mode extension, approve the handoff,
and the bridge takes over: edits stay blocked until the agent calls
`write_goal`, which validates the block, writes `.pi/plan-goal/goal.md`, and
starts `@narumitw/pi-goal` automatically.

### Claude Code

Install as a plugin. The marketplace name is `pi-plan-goal` (from
`claude-code/.claude-plugin/marketplace.json`):

    /plugin marketplace add /absolute/path/to/this-repo/claude-code
    /plugin install plan-goal@pi-plan-goal

Alternative: copy the three hook entries from
[claude-code/settings-snippet.json](claude-code/settings-snippet.json) into
your `settings.json` yourself, replacing `${CLAUDE_PLUGIN_ROOT}` with the
absolute path to `claude-code/`.

Behavior: `PostToolUse` on `ExitPlanMode` drops an approval flag and tells
the model to write `.claude/plan-goal/goal.md`; `PreToolUse` denies any edit
until a validated goal file exists; the `Stop` hook validates the block and
prints `Paste to set the goal:` followed by a `/goal ...` line for you to
paste. Environment variables:

- `PLAN_GOAL_MAX_BLOCKS` (default 3): how many times the Stop hook blocks
  while the goal is missing or invalid before it gives up and only warns.
- `PLAN_GOAL_LOOP=1`: optional self-loop. Instead of just printing the
  `/goal` line, the Stop hook keeps continuing the turn (up to 8
  continuations) until the agent writes `.claude/plan-goal/done` proving
  every row. Use it if you do not want to paste `/goal` yourself.
- `PLAN_GOAL_CHECKER`: override the path to the `goal-block-check` binary.

### Codex

Run the installer from `codex/`:

    bash codex/install.sh              # installs
    bash codex/install.sh --dry-run  # prints actions, writes nothing
    PREFIX=/some/base bash codex/install.sh  # default PREFIX is ~/.codex

It copies `bin/`, `hooks/`, `hooks.json` and `skill/` into
`$PREFIX/plan-goal` and prints what you must do by hand, because Codex
refuses unreviewed hooks:

1. Merge the printed `hooks.json` entries (a `UserPromptSubmit` hook and a
   `Stop` hook) into `~/.codex/hooks.json`, keeping what is already there.
   The installed copy at `$PREFIX/plan-goal/hooks.json` already has real
   absolute paths, so you can merge it verbatim.
2. Copy the skill: `mkdir -p ~/.codex/skills/plan-goal && cp
   $PREFIX/plan-goal/skill/SKILL.md ~/.codex/skills/plan-goal/SKILL.md`
3. Start Codex and run `/hooks` to review and trust both hooks. Re-trust
   after any edit to the scripts.

Behavior: Codex has no plan-exit tool, so approval is conversational. The
`UserPromptSubmit` hook flags an approval when your prompt matches (default:
starts with go/implement/execute/proceed, or contains "implement the plan");
the `Stop` hook then blocks until `.plan-goal/goal.md` validates, then prints
a `/goal ...` line for you to paste. Environment variables:

- `PLAN_GOAL_APPROVE_RE`: regex (case-insensitive) deciding what counts as
  an approval. Default is the pattern above.
- `PLAN_GOAL_MAX_BLOCKS` (default 1): how many times the Stop hook blocks
  per approval before it only warns.
- `PLAN_GOAL_CHECKER`: override the path to the `goal-block-check` binary.

## Verify

    cd pi && npm test && bash uat/headless.sh && bash uat/install.sh
    bash claude-code/uat.sh
    bash codex/uat.sh

Each prints one PASS/FAIL line per case and exits 0 only when all pass. The
pi suite covers the gate, the signal detection and spec parity; headless.sh
drives a real headless pi with a scripted provider; install.sh installs into
a scratch agent dir and boots pi once. The Claude Code and Codex UATs drive
their hooks with fixture JSON on stdin (approval flag, block-on-missing-goal,
loop caps, 4001-char rejection, `/goal` line present).

## Other harnesses (not built)

Seams taken from grounded.md section 5, if you ever extend this:

| Harness | Seam it would use |
|---|---|
| Gemini CLI | Built-in `exit_plan_mode` tool; `AfterTool` hook on it plus an `AfterAgent` decision "deny" loop; the ralph extension is prior art; packaged via `gemini-extension.json` |
| GitHub Copilot CLI | Conversational plan approval; `agentStop` hook with decision "block", max 8 consecutive; `plugin.json` packaging |
| Cursor CLI | `/plan`; `stop` hook returning `followup_message`; `.cursor-plugin/plugin.json` packaging |
| opencode | Plan agent with no approval step; a plugin on `session.idle` re-prompts through the SDK client; npm plugin declared in `opencode.json` |
| Oh My Pi | Native `/plan` (Plan Review) and native `/goal set`; the two modes are mutually exclusive, so a bridge must fully exit plan mode before setting the goal |

## Token cost

Small. The pi bridge injects about 523 characters (roughly 131 tokens) per
handoff. `@narumitw/pi-plan-mode` adds about 1.2k tokens per turn, but only
while planning is active. `@narumitw/pi-goal` adds about 430 tokens per turn
while a goal is active. The Claude Code and Codex hooks inject a few hundred
characters at approval and at stop. (Sources: grounded.md section 3,
wiki/log.md.)
