APPROVE:
Obtained via interactive session (interactive_approve.exp): `claude --model haiku --permission-mode plan --strict-mcp-config`,
prompted Claude to make a plan and call ExitPlanMode, then pressed Enter on the default-highlighted
approval option (option 1, "yes"). Session id bd427112-d7bc-4dbd-bbfa-5db92afb8d99.

Events fired, in order: PreToolUse(ExitPlanMode) -> PermissionRequest(ExitPlanMode) -> Notification
(permission_prompt) -> PostToolUse(ExitPlanMode). PermissionDenied and PostToolUseFailure did NOT fire.

Raw PostToolUse stdin for ExitPlanMode (all keys, plan text trimmed):
{"session_id":"bd427112-d7bc-4dbd-bbfa-5db92afb8d99","transcript_path":"/Users/GaryT/.claude/projects/.../bd427112....jsonl",
"cwd":"/Users/GaryT/.../probe-sandbox","scratchpad_dir":"/private/tmp/claude-501/.../bd427112.../scratchpad",
"prompt_id":"0fcd569a-165d-4cda-be17-5d0a35cc10a8","permission_mode":"acceptEdits","hook_event_name":"PostToolUse",
"tool_name":"ExitPlanMode","tool_input":{},
"tool_response":{"plan":"# Context\n\nUser wants a simple test file created.\n\n# Plan\n\nCreate `hello.txt`... [full markdown, ~400 chars]",
"isAgent":false,"filePath":"/Users/GaryT/.claude/plans/make-a-plan-to-moonlit-harbor.md","hasTaskTool":true},
"tool_use_id":"toolu_01WyzXQbDcHdJj1NzF1ekfzK","duration_ms":2}

Where the plan text lives: at PreToolUse/PermissionRequest it is in tool_input.plan; at PostToolUse
tool_input is emptied to {} and the plan text moves to tool_response.plan (identical markdown).
A plan file path DOES appear: tool_response.filePath, e.g.
/Users/GaryT/.claude/plans/make-a-plan-to-moonlit-harbor.md (a random-name file Claude Code writes
under ~/.claude/plans/ regardless of approval outcome).
Approval visibly flips permission_mode: "plan" at PreToolUse/PermissionRequest -> "acceptEdits" at
PostToolUse.

REJECT:
Obtained via interactive session (interactive_reject.exp): same launch flags, plan requested, but at
the approval prompt pressed Down twice to reach option 3 ("Tell Claude what to change") then Enter,
then typed feedback "No, do not create the file. Cancel this plan." Session id
44738e8a-5bee-4f87-ae68-044df48c9eba.

Events fired for this session, in order: PreToolUse(ExitPlanMode) -> PermissionRequest(ExitPlanMode)
-> Notification(permission_prompt) -> Stop. Confirmed by grepping hooks.log for this session id: only
these 4 event types appear (4 log entries total). PostToolUse did NOT fire, PostToolUseFailure did NOT
fire, PermissionDenied did NOT fire. Rejection is invisible to PostToolUse/PostToolUseFailure/
PermissionDenied hooks; only PreToolUse+PermissionRequest+Notification mark the attempt, and the
session just continues normally (model says "Cancelled — no file created.", then a normal Stop with
permission_mode still "plan" and stop_hook_active:false).

Note: two earlier non-interactive `claude -p --output-format stream-json` attempts (files
approve_test1_stdout.json, reject_test_stdout.json, sessions 15cd3fd5... and 4932abd3...) are NOT true
approve/reject tests — ExitPlanMode was disabled in that config ("ExitPlanMode is disabled for this
session" per the model), so the tool was never called and only Stop fired. Superseded by the
interactive runs above. Exact original command line for those two runs is MISSING (not recorded by
prior agent; inferred only from stream-json content and hooks.log timing).

STOP:
Raw Stop stdin keys (identical set across every capture, both variants): session_id, transcript_path,
cwd, scratchpad_dir, prompt_id, permission_mode, hook_event_name, stop_hook_active,
last_assistant_message, background_tasks, session_crons.

Example (variant B run, session 483f27dd-ce71-4955-8cad-c458a1215a47):
{"session_id":"483f27dd-ce71-4955-8cad-c458a1215a47","transcript_path":"/Users/GaryT/.claude/projects/.../483f27dd....jsonl",
"cwd":"/Users/GaryT/.../probe-sandbox","scratchpad_dir":"/private/tmp/claude-501/.../483f27dd.../scratchpad",
"prompt_id":"8dedd0b7-5ffa-4bac-89e8-3d25d219e4b5","permission_mode":"default","hook_event_name":"Stop",
"stop_hook_active":false,"last_assistant_message":"Hi—what are we building today?","background_tasks":[],
"session_crons":[]}

Both variants blocked stopping and delivered the reason text to the model:
- Variant A (exit 2 + stderr "BLOCK: write probe-sandbox/goal.txt before stopping (variant A, exit 2
  stderr)"): confirmed twice. First interactive run (session bd427112) the model's very next turn said
  "Done. Created `goal.txt` in probe-sandbox to satisfy the stop hook requirement." and goal.txt was
  written with content matching the task description. Two earlier `-p` sessions (in plan mode with
  ExitPlanMode disabled) also received the block text but explicitly refused to act on it, citing plan
  mode restrictions overriding hook feedback — i.e. delivery to the model is confirmed even when the
  model chooses not to comply.
- Variant B (exit 0 + stdout `{"decision":"block","reason":"BLOCK: write probe-sandbox/goal.txt before
  stopping (variant B, stdout JSON)"}`): confirmed via interactive_stopB.exp (session 483f27dd). The
  CLI transcript shows "Ran 5 stop hooks ⎿ Stop hook error: BLOCK: write probe-sandbox/goal.txt before
  stopping (variant B, stdout JSON)" immediately followed by the model's own text: "The stop hook
  requires writing probe-sandbox/goal.txt before I can stop the session. Let me check what's currently
  in the repo and what needs to be written." It then read 4 files, listed 1 directory, and ran 1 shell
  command toward writing goal.txt before the probe script interrupted it (Ctrl-C) to end the session —
  so the full second-Stop/loop-guard firing for variant B specifically was not captured (only one Stop
  event logged for this session), but delivery-and-compliance-attempt is unambiguous. The CLI surfaces
  both variants identically in the transcript, as "Stop hook error: <text>" — there is no UI difference
  between the exit-2/stderr path and the exit-0/stdout-JSON path from the model's perspective.

Loop-guard field: stop_hook_active (boolean), present in every Stop stdin. false on the first Stop
firing of a turn, true on the second Stop firing after the model's follow-up turn (confirmed on 3
separate variant-A sessions: bd427112, 15cd3fd5, 4932abd3 — each shows stop_hook_active:false then
:true across consecutive Stop events for the same session_id/prompt_id lineage). Not MISSING.

COMMANDS:
# Prior agent (inferred from hooks.log markers / file timestamps, exact invocation lines not preserved):
claude -p --output-format stream-json ...   # earliest 2 runs, ExitPlanMode disabled, superseded
expect interactive_approve.exp    # -> interactive_approve_raw.log, hooks.log "APPROVE TEST 2"
expect interactive_reject.exp     # -> interactive_reject_raw.log,  hooks.log "REJECT TEST (interactive)"

# This session (variant B stop test, previously unrun):
cd /Users/GaryT/Documents/Work/tools/pi-plan-goal/claude-code/probe-sandbox
chmod +x interactive_stopB.exp
perl -e 'alarm shift; exec @ARGV' 200 expect interactive_stopB.exp < /dev/null > interactive_stopB.wrapper.log 2>&1
# -> interactive_stopB_raw.log, hooks.log Stop VARIANT:B entry, stop_state_B.txt created

grep -A2 "VARIANT:B" hooks.log
grep -c "44738e8a" hooks.log; grep "44738e8a" hooks.log | grep -o '"hook_event_name":"[A-Za-z]*"'
