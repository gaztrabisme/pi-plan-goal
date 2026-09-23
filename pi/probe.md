# Plan-mode -> Goal bridge: probe findings

Repo clone probed: scratchpad/clones/pi-extensions (pi-plan-mode@0.58.3, pi-goal@0.54.8,
pi 0.87.0). All line refs are relative to that clone's `packages/<pkg>/src/`.

## 1. SIGNAL

SIGNAL: `pi.on("input")` firing with `event.source === "extension"` and `event.text` matching
one of plan-mode's implementation-handoff strings is the reliable edge trigger; the mode
also flips via a `pi.sendMessage()` custom message, customType `"plan-mode-transition"`,
but that message role is NOT one of the roles `message_start`/`message_end` fire for
(docs: user/assistant/toolResult only, extensions.md:667), so a third extension cannot
rely on `message_start` for it — it must read `event.messages` in `pi.on("context")`
(fires every LLM call, extensions.md:723) or use the `input` signal below.

Payload / content, by trigger:
- **"Implement here"** and **"/plan implement"** both call the same `startImplementation`
  (`plan-mode.ts:1178`; `/plan implement` dispatches to it at `plan-mode.ts:325`). It
  publishes the mode contract via `pi.sendMessage(message, {triggerTurn:false})`
  (`plan-mode.ts:947`, customType `"plan-mode-transition"`, content marker
  `[PI PLAN MODE CONTRACT v1: NORMAL]`, `mode-contract.ts:9,31`), THEN sends the actual
  handoff via `pi.sendUserMessage(handoff)` (`plan-mode.ts:960-963`) — this is what fires
  `input` with `event.source === "extension"`. Handoff text (retention=default,
  `fresh-implementation.ts:44-45`):
  `"Plan mode is now disabled. Full tool access is restored. Implement this proposed plan now:\n\n<plan>"`.
  If retention is `clear-on-start`, it's instead `formatHistoryImplementationPrompt()` =
  literal `"Implement the plan."` (`message-transform.ts:9`, used at `plan-mode.ts:1240`).
- **"Start fresh and implement"** (`implementFresh` -> `startFreshImplementation`,
  wired at `plan-mode.ts:217`) is materially different: it calls `ctx.newSession(...)`
  and appends the mode-contract directly via
  `sessionManager.appendCustomMessageEntry(...)` inside `setup:` (`fresh-implementation.ts:141-151`),
  then sends the handoff via `replacementCtx.sendUserMessage(handoff)` inside `withSession:`
  (`fresh-implementation.ts:178`) — **in the newly created session**, not the one the user
  was in. A bridge extension only sees this if its `pi.on("input")` handler is process-global
  (it is — extensions aren't re-registered per session) and it also tracks
  `session_start`/`session_before_switch` to know which session is now current.
  Handoff text there is `formatTransferredPlanPrompt(plan, true)` =
  `"A previous agent produced the plan below to accomplish the user's task. Implement the plan in a fresh context. ..."`
  (`fresh-implementation.ts:52-55,131`).

So: fires for all three, same customType, two different delivery mechanisms (in-session
`pi.sendMessage`+`sendUserMessage` vs. new-session direct entry append), and the actual
message text sent to the model differs by retention setting and by which path.
`input` event fields per extensions.md:1010-1016.

## 2. DISPATCH

DISPATCH: yes — proved empirically, not by reading.

Method: real headless `pi` run (`pi -e <dist/pi-plan-mode> -e <dist/pi-goal> -e <prober.ts>
--provider local-omlx --model Holo-3.1-9B-mtp --mode json --print "/probe"`), local model
served by oMLX (`http://127.0.0.1:8000/v1`, key from `~/.omlx/settings.json` `auth.api_key`;
`/api/status` checked first, `models_loaded:0` before the run, i.e. this forced a real
cold load, not a warm no-op). A third registered command (`/probe`, in a scratch prober
extension) called exactly:
```
pi.sendUserMessage("/goal --tokens 300 Call the goal-completion tool right away with result DONE. Do nothing else.",
  { expandPromptTemplates: true })
```
(option name confirmed against extensions.md:1563-1564: `expandPromptTemplates` — "Dispatch
extension commands ... Defaults to false"). 2.5s later the prober read
`ctx.sessionManager.getEntries()` and found a `customType:"goal-state"` entry with
`data.goal.status === "active"`, `text` equal to the objective string, matching pi-goal's
own registration of `/goal` (`command-registration.ts:25-34,84-86` -> `commands.startGoal`,
`commands.ts:37-118`, `runtime.ts:1168` `appendEntry(GOAL_STATE_ENTRY_TYPE, ...)`). Raw
session-log line and the prober's own JSON dump both captured; the process itself confirms
it (`entry_appended` event, customType `goal-state`, `status:"active"`), run at
`/private/tmp/.../scratchpad/pi-run/{pi-stdout.log,probe-result.json}`. Without
`expandPromptTemplates:true` the same call is inert text per the documented pipeline
(extensions.md:999-1006: extension commands are checked before the `input` event only
when expansion is enabled; commands are otherwise not dispatched from injected text).
ALT: not needed — DISPATCH is yes.

## 3. GOAL_STATE

Session entry, `type:"custom"`, `customType:"goal-state"` (`persistence.ts:8`), written via
`pi.appendEntry(GOAL_STATE_ENTRY_TYPE, serializeGoalState(goal))` (`runtime.ts:1168`, cleared
with `goal:null` at `runtime.ts:1173`). Shape: `{ goal: ActiveGoal | null }`
(`persistence.ts:36-38`, `ActiveGoal` fields at `persistence.ts:14-29`, includes
`status: "active"|...`). A third extension reads it exactly the way pi-goal reads its own
state back (`persistence.ts:66-73`): filter `ctx.sessionManager.getEntries()` (or
`getBranch()`) for `entry.type === "custom" && entry.customType === "goal-state"`, take the
last match. Confirmed live in the DISPATCH run above — no separate proof needed.

## 4. MUTEX

Both packages instantiate their own `WorkflowMutex` over `pi.events`, channel
`"workflow:mutex:v1"`, group `"agent-workflow"` (`pi-plan-mode/src/workflow-mutex.ts:3-4`,
`pi-goal/src/workflow-mutex.ts:3-4` — same protocol, independent instances, one per
extension, coordinating via emit/answer on the shared bus, not a real cross-process lock).

- `pi-goal`'s `/goal start` acquires this mutex as the FIRST thing it does
  (`commands.ts:78`: `if (!this.runtime.acquireWorkflow(...)) return this.reportWorkflowBusy(ctx)`)
  — if plan-mode still holds it, `/goal start` fails with a "busy" notice instead of starting.
- plan-mode's `startImplementation` releases its own ownership only AFTER the handoff
  message is sent, in the same synchronous call (`plan-mode.ts:1243-1256`:
  `sendPlanModeUserMessage(...)` then `if (wasEnabled) releaseWorkflowOwner()`). Since
  `pi.on("input")` delivery is not synchronous with that call, by the time any listener
  reacts to the handoff, the mutex is already free — so a bridge reacting to the SIGNAL
  above and then dispatching `/goal` should not race plan-mode for the mutex in practice,
  but this is a timing argument, not something re-proven in the DISPATCH run (that run
  never loaded plan-mode's own tool gate, only pi-goal's dispatch path).
- Plan-mode's own edit gate is already off at handoff time: `state.enabled = false` and
  `publishModeContract("normal", ctx)` both happen at `plan-mode.ts:1205-1213`, BEFORE
  `sendPlanModeUserMessage` and before the mutex release. So yes — by the time the bridge
  could act, plan-mode's restriction is already lifted; plan-mode will not hold the line
  for the bridge.
- The bridge can and should use `pi.on("tool_call") -> {block:true, reason}`
  (extensions.md:864-905) without touching `"agent-workflow"` at all. That mutex only
  arbitrates between plan-mode and pi-goal so they don't both drive the same session
  autonomously; it is not a general edit gate and nothing requires a third extension to
  join it. **The bridge must NOT acquire the `"agent-workflow"` group for its own bookkeeping**
  — doing so would make pi-goal's own `acquireWorkflow()` in `startGoal` fail (busy) right
  after the bridge's dispatch, since it's a single named group with one owner at a time.

## 5. INSTALL

Worked, real commands, in the already-cloned monorepo (not `pi install`, since both packages
are local workspace members there):
```
cd .../scratchpad/clones/pi-extensions
npm install --no-audit --no-fund                       # 522 packages, 7s
npm run build --workspace=@narumitw/pi-tui-kit
npm run build --workspace=@narumitw/pi-plan-mode        # -> packages/pi-plan-mode/dist/index.ts
npm run build --workspace=@narumitw/pi-goal             # -> packages/pi-goal/dist/index.ts
```
Then loaded straight off disk, no `~/.pi` touched:
```
PI_CODING_AGENT_DIR=<scratch>/pi-run/agentdir pi \
  -e packages/pi-plan-mode/dist/index.ts \
  -e packages/pi-goal/dist/index.ts \
  -e <scratch>/pi-run/prober.ts \
  --no-skills --no-prompt-templates --no-themes --no-context-files --no-session \
  --provider local-omlx --model Holo-3.1-9B-mtp --mode json --print --approve "/probe"
```
(`local-omlx` registered inside `prober.ts` via `pi.registerProvider`, extensions.md:1852-1873
object form, pointed at the oMLX endpoint.) Exit 0; see DISPATCH section for result.
