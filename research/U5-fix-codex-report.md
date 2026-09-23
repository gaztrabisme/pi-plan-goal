# U5 fix report — codex/ (H5, H6)

Verdict: PASS. `bash codex/uat.sh` exits 0 with all 11 cases PASS (a–h plus new i, j, k).
Writes were confined to codex/. research/review.md findings H5 and H6 no longer reproduce
(re-run of both repro shapes is below).

## Changed files

- `codex/hooks/pre-tool-use.sh` (new, executable) — the H5 pre-tool gate.
- `codex/hooks.json` — registers the gate as a third hook: `PreToolUse` with
  matcher `^(Bash|apply_patch|Edit|Write)$`, timeout 10, placeholder command
  `__PLAN_GOAL_DIR__/hooks/pre-tool-use.sh`.
- `codex/install.sh` — the H6 fix: the installed hooks.json is now generated with a
  python3 heredoc (`json.load` of the template, `__PLAN_GOAL_DIR__` replaced by the
  destination, each command passed through `shlex.quote`, written with `json.dump`);
  the old `sed` rewrite is gone. Install exits 2 with a clear message if python3 is
  missing (before any file is touched); `--dry-run` still needs no python3. The printed
  merge instructions now show all three registrations with shell-quoted command paths
  (POSIX `sh_quote` helper) and say "three new hooks".
- `codex/uat.sh` — cases i, j, k added; header updated.

## H5 — PreToolUse gate

Active while `<cwd>/.plan-goal/approved` exists AND `.plan-goal/goal.md` is missing or
fails `PLAN_GOAL_CHECKER` (default `codex/bin/goal-block-check`); otherwise exit 0
silently.

- Denied tools: `apply_patch` (the docs note hook input reports file edits as
  `tool_name: "apply_patch"`; `Edit`/`Write` are only matcher aliases) plus defensive
  `Edit`/`Write`/`MultiEdit`/`NotebookEdit` names. A patch is allowed only when every
  `*** Add/Update/Delete/Move File:` path normalizes under `<cwd>/.plan-goal/`
  (`Move` checks both endpoints); an unrecognizable patch fails closed.
- Denied Bash: any command that is not read-only and not plan-goal-only.
  Read-only = every segment (split on newline `;` `&&` `||` `|`) starts with cat head
  tail ls grep rg find pwd wc echo test or `git status/log/diff`; no `>`/`>>`/`tee`
  anywhere; no `$(` or backtick; find without `-exec/-execdir/-delete/-ok/-fprint/-fls`;
  git diff without `--output`/`--output=…`. Plan-goal-only = a closed head set
  (printf/echo/cat redirect-checked, mkdir/touch/rm/mv/cp/tee with all non-flag words
  under `.plan-goal/`, or the checker itself) with every redirection target under
  `.plan-goal/`; leftover `2>`/`>&`-style tokens fail closed. Quoted `|`/`;` fail closed
  (naive segment split), matching the H1 lesson.
- Fail closed: without python3 (or if mktemp fails/INT TERM hits) while the approved
  flag exists, the wrapper exits 2 with the reason on stderr before Python runs.

### Deny output shape and its source

From `codex/.docs-hooks.md` (notes from the official hooks docs, "PreToolUse" section,
lines 763–773): plain text on stdout is ignored; to deny, return

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "…"
  }
}
```

The gate emits exactly this (with exit 0). The docs also name exit code 2 + stderr as
the alternative blocking convention (line 784) — that is what the fail-closed path uses.
The reason text includes the goal-block-check problems so the model can fix the block.

## H6 — installer

`shlex.quote(dest + "/hooks/<name>.sh")` inside `json.dump`: a PREFIX with spaces or
quotes yields valid JSON and a launchable command. UAT case k installs into
`…/k prefix's dir` (space + single quote), parses the generated hooks.json, and runs the
Stop command string via `sh -c` against a flag+valid-goal fixture (asserts the `/goal
Execute plan` systemMessage).

## UAT (bash codex/uat.sh)

```
PASS a UserPromptSubmit approval
PASS b Stop blocks once for a missing goal
PASS c Stop loop guard
PASS d Stop with a valid goal
PASS e Stop blocks on the 4001-char goal
PASS f SKILL.md frontmatter
PASS g goal-block-check copy
PASS h install.sh --dry-run under PREFIX
PASS i PreToolUse gate with no valid goal
PASS j PreToolUse gate with a valid goal
PASS k install.sh with spaces and quotes in PREFIX

plan-goal UAT: all cases passed
```

exit 0. Case i additionally covers: `ls` allowed, `find . -delete` denied,
`printf x > f` denied, a `.plan-goal/`-only patch and command allowed silently, a
mutating call with no approval flag allowed silently, and missing python3 + flag →
exit 2 with stderr reason.

## Repro re-check (research/review.md shapes)

- H5: events are now `PreToolUse,UserPromptSubmit,Stop`; with the flag armed,
  apply_patch and `printf … > edited.txt` both get `permissionDecision: "deny"`;
  `edited.txt` is not created; Stop still blocks once for the missing goal.
- H6 space: `PREFIX="$(mktemp -d)/plan goal install"` → hooks.json valid, Stop command
  `sh -c` exit 0, empty stderr (was exit 127, `/tmp/.../plan: No such file`).
- H6 quote: `PREFIX="$(mktemp -d)/quoted \" path"` → hooks.json valid, all three events
  present, Stop command `sh -c` exit 0 (was invalid JSON at line 9).

## Notes

- `wiki/log.md` shows uncommitted modifications from the earlier parallel H1 (pi) and
  H2–H4 (claude-code) fix sessions — not part of this change, left untouched.
- Nothing outside codex/ was written; no git commands run.
