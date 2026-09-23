/**
 * pi-plan-goal: bridges @narumitw/pi-plan-mode's implementation handoff to
 * @narumitw/pi-goal, forcing a goal block to be recorded before any edit.
 *
 * See ../probe.md for the measured seam this relies on:
 *   1. SIGNAL  - plan-mode's handoff fires pi.on("input") with
 *                event.source === "extension" (signal.ts).
 *   2. DISPATCH - pi.sendUserMessage("/goal <text>", {expandPromptTemplates:true})
 *                 starts pi-goal (proved empirically).
 *   3. GOAL_STATE - pi-goal's state lives in a "goal-state" custom entry.
 *   4. MUTEX - this bridge must not join pi-goal/plan-mode's
 *              "workflow:mutex:v1" "agent-workflow" group.
 */

import { mkdir, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";
import { GATED_TOOL_NAMES, gateToolCall } from "./gate.ts";
import { GOAL_BLOCK_MAX_CHARS, validateGoalBlock } from "./goal-block.ts";
import { isHandoffSignal } from "./signal.ts";

const STATE_TYPE = "plan-goal-state";
const GOAL_FILE_REL = ".pi/plan-goal/goal.md";
const GOAL_COMMAND_NAME = "goal";
const STEER_TEXT =
  "Before making any edit or write, call write_goal with the goal block for this approved plan (see spec/goal-block.md).";

// Hard ceiling on the raw tool argument, well above the real 4000-char rule
// (spec/goal-block.md). Schema-level maxLength rejects before execute() runs
// with a generic "must not have more than N characters" message, so it can't
// be the real limit's enforcement point - only a sanity cap against
// pathological payloads. The real rule, with the exact wording the spec
// requires ("too long: 4001/4000 characters"), is enforced at runtime below
// by validateGoalBlock, ported line-for-line from bin/goal-block-check.
const RAW_ARG_CEILING = GOAL_BLOCK_MAX_CHARS * 4;

interface PlanGoalState {
  armed: boolean;
}

export default function planGoalExtension(pi: ExtensionAPI) {
  let armed = false;
  let pendingArm = false;

  function persist(next: boolean) {
    armed = next;
    pi.appendEntry<PlanGoalState>(STATE_TYPE, { armed });
  }

  function restore(ctx: ExtensionContext) {
    let last: PlanGoalState | undefined;
    for (const entry of ctx.sessionManager.getBranch()) {
      if (entry.type === "custom" && entry.customType === STATE_TYPE) {
        last = entry.data as PlanGoalState;
      }
    }
    armed = last?.armed ?? false;
  }

  pi.on("session_start", async (_event, ctx) => {
    restore(ctx);
  });

  pi.on("input", (event) => {
    if (!isHandoffSignal(event)) return;
    // Defer the actual arm (pi.appendEntry) to turn_start: calling it
    // synchronously here, before the handoff message's own session entry is
    // committed, empirically corrupts entry parentage and crashes
    // turn_end ("could not resolve the persisted assistant entry ID").
    // Steer by appending to the handoff text itself (returning it here is
    // not an API call, just the input transform result) rather than
    // injecting a separate pi.sendMessage() alongside it.
    pendingArm = true;
    return {
      action: "transform",
      text: `${event.text}\n\n${STEER_TEXT}`,
    };
  });

  pi.on("turn_start", () => {
    if (!pendingArm) return;
    pendingArm = false;
    persist(true);
  });

  pi.on("tool_call", (event) => {
    if (!armed) return;
    if (GATED_TOOL_NAMES.has(event.toolName) || event.toolName === "bash") {
      return gateToolCall(event.toolName, event.input);
    }
  });

  pi.registerTool({
    name: "write_goal",
    label: "Write Goal",
    description:
      "Record the goal block for an approved plan and start tracking it with pi-goal. See spec/goal-block.md for the block format.",
    promptSnippet: "Record the approved plan's goal block and start goal tracking",
    promptGuidelines: [
      "Call write_goal with the plan's goal block before any edit or write once a plan has been approved.",
    ],
    parameters: Type.Object({
      block: Type.String({ maxLength: RAW_ARG_CEILING }),
    }),
    async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
      const problems = validateGoalBlock(params.block);
      if (problems.length > 0) {
        throw new Error(problems.join("\n"));
      }

      const goalPath = resolve(ctx.cwd, GOAL_FILE_REL);
      await mkdir(dirname(goalPath), { recursive: true });
      const text = params.block.endsWith("\n") ? params.block : `${params.block}\n`;
      await writeFile(goalPath, text, "utf8");

      const hasGoalCommand = pi.getCommands().some((command) => command.name === GOAL_COMMAND_NAME);
      if (!hasGoalCommand) {
        persist(false);
        return {
          content: [
            {
              type: "text",
              text: `Wrote ${GOAL_FILE_REL}. pi-goal is not installed, so goal tracking was not started.`,
            },
          ],
          details: {},
        };
      }

      pi.sendUserMessage(`/${GOAL_COMMAND_NAME} ${params.block}`, {
        expandPromptTemplates: true,
        deliverAs: "followUp",
      });
      persist(false);

      return {
        content: [{ type: "text", text: `Wrote ${GOAL_FILE_REL} and started goal tracking.` }],
        details: {},
      };
    },
  });
}
