#!/usr/bin/env node
/**
 * Assertions for uat/headless.sh. Reads the pi --mode json event stream and
 * the run's cwd, prints one PASS/FAIL line per step, and exits 0 only if
 * every step passed.
 *
 * Usage: node check-headless.mjs <out.jsonl> <cwd> <pi-exit-status>
 */

import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";

const [, , outPath, cwd, piExitStatus] = process.argv;

const lines = readFileSync(outPath, "utf8").split("\n").filter(Boolean);
const events = lines.map((line) => JSON.parse(line));

const toolEvents = events.filter((e) => e.type === "tool_execution_end");
const goalEntries = events
  .filter((e) => e.type === "entry_appended" && e.entry?.customType === "goal-state")
  .map((e) => e.entry.data);

let allPassed = true;
function check(label, condition, detail) {
  if (condition) {
    console.log(`PASS: ${label}`);
  } else {
    allPassed = false;
    console.log(`FAIL: ${label}${detail ? ` (${detail})` : ""}`);
  }
}

check("pi process exited 0", piExitStatus === "0", `exit status was ${piExitStatus}`);

const editResult = toolEvents.find((e) => e.toolName === "edit");
const editText = editResult ? JSON.stringify(editResult.result) : "";
check(
  "(a) edit is blocked with a reason mentioning write_goal",
  Boolean(editResult?.isError) && editText.includes("write_goal"),
  editResult ? `isError=${editResult.isError} result=${editText.slice(0, 200)}` : "no edit tool_execution_end seen",
);

const writeGoalResults = toolEvents.filter((e) => e.toolName === "write_goal");
const tooLongResult = writeGoalResults.find((e) => e.isError);
const tooLongText = tooLongResult ? JSON.stringify(tooLongResult.result) : "";
check(
  "(b) write_goal with the too-long fixture errors mentioning 4001",
  Boolean(tooLongResult) && tooLongText.includes("4001"),
  tooLongResult ? `result=${tooLongText.slice(0, 200)}` : "no failing write_goal tool_execution_end seen",
);

const okResult = writeGoalResults.find((e) => !e.isError);
check(
  "(c) write_goal with the valid example block succeeds",
  Boolean(okResult),
  okResult ? undefined : "no successful write_goal tool_execution_end seen",
);

const writeResult = toolEvents.find((e) => e.toolName === "write" && !e.isError);
const markerPath = join(cwd, "output", "marker.txt");
check(
  "(d) write succeeds after disarm and the file exists on disk",
  Boolean(writeResult) && existsSync(markerPath),
  `tool_execution_end seen=${Boolean(writeResult)} fileExists=${existsSync(markerPath)}`,
);

const goalPath = join(cwd, ".pi", "plan-goal", "goal.md");
check("goal.md was written to .pi/plan-goal/goal.md", existsSync(goalPath));

const activeGoal = goalEntries.find((data) => data?.goal?.status === "active");
check(
  "a goal-state entry with status \"active\" exists (pi-goal was actually dispatched)",
  Boolean(activeGoal),
  `goal-state entries seen=${goalEntries.length}`,
);

process.exit(allPassed ? 0 : 1);
