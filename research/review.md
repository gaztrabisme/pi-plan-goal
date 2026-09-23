# U5 — adversarial review of plan→goal bridges

Review date: 2026-09-23. Code remained read-only; probe data used temporary directories.

## Findings

| ID | Severity | Package | Finding | Repro (exact command) | Observed | Suggested fix |
|---|---|---|---|---|---|---|
| H1 | HIGH | pi | Bash allowlist accepts mutating find/git diff options and fails to split newlines. | <code>node --input-type=module -e 'import{mkdtempSync,writeFileSync,existsSync}from"node:fs";import{tmpdir}from"node:os";import{join}from"node:path";import{execFileSync}from"node:child_process";import{isMutatingBash}from"./pi/src/gate.ts";const d=mkdtempSync(join(tmpdir(),"u5-pi-")),p=join(d,"victim"),c="find "+d+" -type f -delete";writeFileSync(p,"x");console.log(isMutatingBash(c));execFileSync("bash",["-c",c]);console.log(existsSync(p))'</code> | Printed false then false; the victim was deleted. git diff --output wrote 386 bytes; newline + rm removed its marker. | Fail closed on compound or unparsed shell syntax; allow only parsed read-only commands with restricted arguments. |
| H2 | HIGH | claude-code | Bash is outside the PreToolUse matcher; redirection edits bypass the gate with no goal. | <code>d=$(mktemp -d); mkdir -p "$d/.claude/plan-goal"; : >"$d/.claude/plan-goal/approved"; (cd "$d" &amp;&amp; bash -c 'printf "written before goal\n" &gt; edited.txt')</code> | Matcher was Edit/Write/MultiEdit/NotebookEdit; edited.txt was written while goal.md was absent. | Cover Bash and every write-capable tool, or state that the gate covers only Edit/Write tools. |
| H3 | HIGH | claude-code | Missing python3 makes PreToolUse exit 127 with no deny output; this fails open. | <code>PATH="$d/bin" /bin/sh claude-code/hooks/pre-edit-gate.sh &lt; input.json</code> after creating d/bin with only dirname/mktemp/cat/rm symlinks | rc=127, stdout 0 bytes, stderr says python3 not found. Claude documents that other exit codes or hooks that cannot start do not block PreToolUse. | Check dependencies and exit 2 before running Python, or remove the runtime Python dependency. |
| H4 | HIGH | claude-code | A valid goal from an earlier plan remains at goal.md, so a new approval lets edits through before the new goal exists. | <code>cp spec/example.md "$d/.claude/plan-goal/goal.md"; printf '{"cwd":"%s","tool_response":{"plan":"# New plan","filePath":"plans/new.md"}}\n' "$d" \| bash claude-code/hooks/post-exit-plan.sh; printf '{"cwd":"%s","tool_input":{"file_path":"src/new.py"}}\n' "$d" \| bash claude-code/hooks/pre-edit-gate.sh</code> | New approval flag existed; pre-edit output was empty (allowed); stored goal still named the old plan. | Delete the old goal on approval or bind validity to the approved plan/session identity. |
| H5 | HIGH | codex | hooks.json contains only UserPromptSubmit and Stop; there is no pre-edit gate for Bash/Edit/Write. | <code>printf '{"prompt":"Implement the plan","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh; (cd "$d" &amp;&amp; bash -c 'printf "edited before goal\n" &gt; edited.txt')</code> | Approval flag existed and file was written before Stop returned decision:block. | Add a pre-tool gate for every mutating tool supported by the runtime; Stop only sees the state after edits. |
| H6 | HIGH | codex | Installer writes an unquoted command path into hooks.json: spaces make the command fail to launch and quotes make hooks.json invalid. | <code>base=$(mktemp -d)/'plan goal install'; PREFIX="$base" bash codex/install.sh; sh -c "$command"</code> | With a space in PREFIX, exit 127 (/tmp/.../plan not found); with a quote, JSON parsing failed at line 9. Hooks do not run. | JSON-escape the path and generate a shell-safe command; test install paths containing spaces and quotes. |
| H7 | HIGH | codex | Reinstall deletes extra files under the package destination’s bin/hooks/hooks.json/skill directories. | <code>p=$(mktemp -d); mkdir -p "$p/plan-goal/hooks"; printf 'local customization\n' &gt; "$p/plan-goal/hooks/custom-hook.sh"; PREFIX="$p" bash codex/install.sh</code> | Custom hook disappeared; package hook was installed; root PREFIX/hooks.json survived. | Stage upgrades and preserve unknown files, or back up/stop when the destination contains files not owned by the package. |
| M1 | MED | pi / validator | TS and canonical checker disagree on Unicode decimal digits: the checker accepts Arabic-Indic ١; TS rejects it. | <code>node --input-type=module -e 'import{validateGoalBlock}from"./pi/src/goal-block.ts";import{spawnSync}from"node:child_process";const n=String.fromCharCode(10),s="Execute plan \"x\" (p). Goal rows:"+n+"١ check: test -f x",p=spawnSync("./bin/goal-block-check",["-"],{input:s,encoding:"utf8"});console.log(JSON.stringify(validateGoalBlock(s)),p.status)'</code> | TS returned free text before row 1/no goal rows; bin/goal-block-check exited 0. | Use ASCII [0-9] in both validators or align Unicode-number handling and add a parity case. |
| M2 | MED | all validators | CRLF text is rejected because carriage return remains on the header line. | <code>node --input-type=module -e 'import{validateGoalBlock as v}from"./pi/src/goal-block.ts";import{spawnSync as s}from"node:child_process";const b="Execute plan \"x\" (p). Goal rows:"+String.fromCharCode(13,10)+"1 check: test -f x";console.log(JSON.stringify(v(b)),s("./bin/goal-block-check",["-"],{input:b,encoding:"utf8"}).status)'</code> | TS and checker both reported missing header line for an otherwise valid block. | Normalize CRLF to LF before extraction and validation. |
| M3 | MED | codex | Approval state is cwd-scoped, not session-scoped; session B consumes session A’s approval. | <code>d=$(mktemp -d); printf '{"session_id":"session-A","prompt":"Implement plan A","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh; printf '{"session_id":"session-B","hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" \| bash codex/hooks/stop.sh</code> | Session B got decision:block; shared approval flag remained. | Key state by validated session ID and have Stop read only that session’s approval. |
| M4 | MED | codex | New approval does not clear goal.md; a valid old goal is accepted and emitted for the new plan. | <code>d=$(mktemp -d); mkdir -p "$d/.plan-goal"; cp spec/example.md "$d/.plan-goal/goal.md"; printf '{"prompt":"Implement the plan for the new feature","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh; printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" \| bash codex/hooks/stop.sh</code> | Stop emitted the old plan’s /goal line and removed the new approval flag. | Clear stale goal state on approval and scope each goal to its plan/session. |
| M5 | MED | codex | Checker accepts a canonical full plan by extracting Goal block, but Stop does not extract it before building /goal. | <code>bash codex/bin/goal-block-check "$d/.plan-goal/goal.md"; printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" \| bash codex/hooks/stop.sh</code> after writing the fixture shown below | Checker exited 0; Stop emitted /goal # Canonical plan and cleared approval rather than forwarding the validated block. | Reuse the validator extraction logic when building the paste command, or reject full documents consistently. |
| M6 | MED | codex | Missing-goal block counter is not reset by a new approval; a new plan inherits the prior plan’s exhausted counter. | <code>d=$(mktemp -d); printf '{"prompt":"Implement plan one","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh; printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" \| bash codex/hooks/stop.sh; printf '{"prompt":"Implement plan two","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh; printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" \| bash codex/hooks/stop.sh</code> | Plan one got decision:block; plan two’s first Stop had no decision and only the “not blocking again after 1 of 1” message. | Reset blocks and stale goal state on every new approval. |
| M7 | MED | codex | The default approval regex treats a question about implementing the plan as an approval. | <code>d=$(mktemp -d); printf '{"prompt":"Can you explain whether we should implement the plan later?","cwd":"%s"}\n' "$d" \| bash codex/hooks/user-prompt-submit.sh</code> | Hook created .plan-goal/approved and returned Plan approved context. | Require an explicit affirmative command/state instead of matching any occurrence of “implement the plan.” |

## HIGH repro details

### H1 — pi bash allowlist bypass

Run from the repository root:

    node --input-type=module -e 'import{mkdtempSync,writeFileSync,existsSync}from"node:fs";import{tmpdir}from"node:os";import{join}from"node:path";import{execFileSync}from"node:child_process";import{isMutatingBash}from"./pi/src/gate.ts";const d=mkdtempSync(join(tmpdir(),"u5-pi-")),p=join(d,"victim"),c="find "+d+" -type f -delete";writeFileSync(p,"x");console.log("gate_blocks="+isMutatingBash(c)+" command="+c);execFileSync("bash",["-c",c]);console.log("victim_exists="+existsSync(p))'

Observed:

    gate_blocks=false command=find /var/folders/yy/s3_y_d5x2_34qb0k9f6qvjqr0000gn/T/u5-pi-sF4Jeq -type f -delete
    victim_exists=false

Additional actual probes: command string cat /dev/null followed by a newline and rm -f <marker> returned non-mutating and deleted the marker. git diff --no-index <before> <after> --output=<out> returned non-mutating and created a 386-byte file.

### H2 — Claude Code Bash matcher gap

    set -eu
    d=$(mktemp -d /tmp/u5-claude-bash.XXXXXX)
    mkdir -p "$d/.claude/plan-goal"
    : >"$d/.claude/plan-goal/approved"
    python3 -c 'import json; print("; ".join(x["matcher"] for x in json.load(open("claude-code/hooks/hooks.json"))["hooks"]["PreToolUse"]))'
    (cd "$d" && bash -c 'printf "written by Bash before goal\n" > edited.txt')
    printf 'goal_exists=%s edited=%s\n' "$(test -f "$d/.claude/plan-goal/goal.md" && echo yes || echo no)" "$(cat "$d/edited.txt")"

Observed:

    Edit|Write|MultiEdit|NotebookEdit
    goal_exists=no edited=written by Bash before goal

### H3 — Claude Code missing Python fails open

This gives the hook dirname, mktemp, cat, and rm, but deliberately omits Python:

    set -u
    d=$(mktemp -d /tmp/u5-no-python.XXXXXX)
    mkdir -p "$d/bin" "$d/.claude/plan-goal"
    : >"$d/.claude/plan-goal/approved"
    for x in dirname mktemp cat rm; do ln -s "$(command -v "$x")" "$d/bin/$x"; done
    printf '{"cwd":"%s","tool_input":{"file_path":"src/new.py"}}\n' "$d" | PATH="$d/bin" /bin/sh claude-code/hooks/pre-edit-gate.sh >"$d/out" 2>"$d/err"; rc=$?
    printf 'rc=%s stdout_bytes=%s stderr=%s\n' "$rc" "$(wc -c <"$d/out" | tr -d ' ')" "$(head -n1 "$d/err")"

Observed: rc=127, stdout_bytes=0, stderr says python3: command not found. Claude’s official [hook exit-code reference](https://code.claude.com/docs/en/hooks#other-exit-codes) documents that other exit codes and hooks that cannot start do not block PreToolUse.

### H4 — Claude Code reuses an old valid goal

    set -eu
    d=$(mktemp -d /tmp/u5-claude-stale.XXXXXX)
    mkdir -p "$d/.claude/plan-goal"
    cp spec/example.md "$d/.claude/plan-goal/goal.md"
    printf '{"cwd":"%s","tool_response":{"plan":"# New plan","filePath":"plans/new.md"}}\n' "$d" | bash claude-code/hooks/post-exit-plan.sh >"$d/post.json"
    printf '{"cwd":"%s","tool_input":{"file_path":"src/new.py"}}\n' "$d" | bash claude-code/hooks/pre-edit-gate.sh >"$d/pre.json"
    printf 'approved=%s old_goal=%s pre_hook_output_bytes=%s\n' "$(test -f "$d/.claude/plan-goal/approved" && echo yes)" "$(head -n1 "$d/.claude/plan-goal/goal.md")" "$(wc -c <"$d/pre.json" | tr -d ' ')"

Observed: approved=yes; the old goal header remained; pre_hook_output_bytes=0, so the new edit was allowed.

### H5 — Codex has no pre-edit gate

    set -eu
    d=$(mktemp -d /tmp/u5-codex-bypass.XXXXXX)
    printf '{"prompt":"Implement the plan","cwd":"%s"}\n' "$d" | bash codex/hooks/user-prompt-submit.sh >"$d/prompt.out"
    python3 -c 'import json; print(",".join(json.load(open("codex/hooks.json"))["hooks"]))'
    (cd "$d" && bash -c 'printf "edited before goal\n" > edited.txt')
    printf 'armed=%s edited=%s\n' "$(test -f "$d/.plan-goal/approved" && echo yes)" "$(cat "$d/edited.txt")"
    printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" | bash codex/hooks/stop.sh

Observed configured events were UserPromptSubmit,Stop; output was armed=yes edited=edited before goal, followed by a Stop decision:block. The edit happened before that Stop decision.

### H6 — Codex install paths can disable the hooks

Space-path reproduction:

    set -eu
    base=$(mktemp -d /tmp/u5-prefix.XXXXXX)/'plan goal install'
    mkdir -p "$base"
    PREFIX="$base" bash codex/install.sh >/dev/null
    command=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["hooks"]["Stop"][0]["hooks"][0]["command"])' "$base/plan-goal/hooks.json")
    rc=0
    sh -c "$command" </dev/null >/tmp/u5-prefix.out 2>/tmp/u5-prefix.err || rc=$?
    printf 'exec_exit=%s stderr=%s\n' "$rc" "$(head -n1 /tmp/u5-prefix.err)"

Observed: exit 127, sh: /tmp/u5-prefix.../plan: No such file or directory. A second run with PREFIX containing quoted " path made hooks.json fail JSON parsing (Expecting ',' delimiter, line 9).

Quote-path reproduction:

    set -eu
    base=$(mktemp -d /tmp/u5-prefixq.XXXXXX)/'quoted " path'
    mkdir -p "$base"
    PREFIX="$base" bash codex/install.sh >/dev/null
    python3 - "$base/plan-goal/hooks.json" <<'PY'
    import json, sys
    try:
        json.load(open(sys.argv[1], encoding="utf-8"))
        print("hooks_json=valid")
    except Exception as err:
        print("hooks_json=invalid:", err)
    PY

Observed: hooks_json=invalid: Expecting ',' delimiter: line 9 column 57.

### H7 — Codex reinstall deletes custom files in its install directory

    set -eu
    p=$(mktemp -d /tmp/u5-codex-install.XXXXXX)
    mkdir -p "$p/plan-goal/hooks" "$p/skills"
    printf 'local customization\n' >"$p/plan-goal/hooks/custom-hook.sh"
    printf '{"hooks":{"UserPromptSubmit":[]},"keep":true}\n' >"$p/hooks.json"
    PREFIX="$p" bash codex/install.sh >/dev/null
    printf 'custom_hook_survives=%s root_hooks_json_survives=%s package_hook_installed=%s\n' "$(test -f "$p/plan-goal/hooks/custom-hook.sh" && echo yes || echo no)" "$(grep -q '"keep":true' "$p/hooks.json" && echo yes || echo no)" "$(test -f "$p/plan-goal/hooks/stop.sh" && echo yes || echo no)"

Observed: custom_hook_survives=no root_hooks_json_survives=yes package_hook_installed=yes. The root hooks config was not clobbered; extra files within the package destination’s managed subdirectories were removed.

### M5 — full-plan extraction reproduction

    set -eu
    d=$(mktemp -d /tmp/u5-codex-extract.XXXXXX)
    mkdir -p "$d/.plan-goal"
    : >"$d/.plan-goal/approved"
    cat >"$d/.plan-goal/goal.md" <<'EOF'
    # Canonical plan
    ## Goal block
    Execute plan "x" (p). Goal rows:
    1 check: test -f x
    ## Working pattern
    extra text
    EOF
    bash codex/bin/goal-block-check "$d/.plan-goal/goal.md"
    printf '{"hook_event_name":"Stop","stop_hook_active":false,"cwd":"%s"}\n' "$d" | bash codex/hooks/stop.sh >"$d/out.json"
    python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["systemMessage"])' "$d/out.json"

Observed: checker exited 0; Stop printed “Paste to set the goal:” followed by “/goal # Canonical plan”.

## Run notes

- cd pi && npm test: pass, 23/23 tests.
- cd pi && bash uat/headless.sh: failed because npm could not resolve registry.npmjs.org while fetching @narumitw/pi-goal; later assertions failed because the dependency did not load.
- cd pi && bash uat/install.sh: failed fetching @narumitw/pi-plan-mode and @narumitw/pi-goal for the same ENOTFOUND; installing the local bridge package and starting pi succeeded.
- bash claude-code/uat.sh: pass, cases a–j.
- bash codex/uat.sh: pass, cases a–h.
- No infinite loop reproduced: Claude’s UAT released after its 8-continuation loop cap; Codex’s second Stop followed stop_hook_active guard. Validator accepted a 4,000-code-point emoji block and rejected 4,001.
- Injection probe: a title containing $(), backticks, and shell punctuation produced valid JSON without creating the shell marker; a ../../ plan filePath did not write outside the hook state directory.

HIGH count: 7
