/**
 * Parity between the TypeScript port (src/goal-block.ts) and the reference
 * shell validator (../../bin/goal-block-check), run over the same fixtures.
 */

import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import assert from "node:assert/strict";
import test from "node:test";
import { validateGoalBlock } from "../src/goal-block.ts";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const CHECK_BIN = join(ROOT, "bin", "goal-block-check");

const FIXTURES = [
  join(ROOT, "spec", "example.md"),
  join(ROOT, "spec", "fixtures", "too-long.md"),
  join(ROOT, "spec", "fixtures", "no-check.md"),
  join(ROOT, "spec", "fixtures", "gap.md"),
];

function runShellCheck(file: string): { exitCode: number; stderr: string } {
  const result = spawnSync(CHECK_BIN, [file], { encoding: "utf8" });
  return { exitCode: result.status ?? -1, stderr: result.stderr };
}

for (const file of FIXTURES) {
  test(`validateGoalBlock parity: ${file}`, () => {
    const raw = readFileSync(file, "utf8");
    const problems = validateGoalBlock(raw);
    const shell = runShellCheck(file);

    if (problems.length === 0) {
      assert.equal(shell.exitCode, 0, `shell validator disagreed (exit ${shell.exitCode}): ${shell.stderr}`);
    } else {
      assert.equal(shell.exitCode, 1, `shell validator disagreed (exit ${shell.exitCode}): ${shell.stderr}`);
      const shellLines = shell.stderr.split("\n").filter(Boolean);
      assert.deepEqual(problems, shellLines);
    }
  });
}

test("validateGoalBlock: valid example.md has no problems", () => {
  const raw = readFileSync(join(ROOT, "spec", "example.md"), "utf8");
  assert.deepEqual(validateGoalBlock(raw), []);
});

test("validateGoalBlock: too-long fixture reports the exact 4001/4000 wording", () => {
  const raw = readFileSync(join(ROOT, "spec", "fixtures", "too-long.md"), "utf8");
  const problems = validateGoalBlock(raw);
  assert.ok(
    problems.includes("too long: 4001/4000 characters"),
    `expected the 4001/4000 wording, got: ${JSON.stringify(problems)}`,
  );
});

test("validateGoalBlock: row without a check is rejected", () => {
  const raw = readFileSync(join(ROOT, "spec", "fixtures", "no-check.md"), "utf8");
  const problems = validateGoalBlock(raw);
  assert.ok(problems.some((p) => p.includes("missing check after ':'")));
});

test("validateGoalBlock: numbering gap is rejected", () => {
  const raw = readFileSync(join(ROOT, "spec", "fixtures", "gap.md"), "utf8");
  const problems = validateGoalBlock(raw);
  assert.ok(problems.some((p) => p.includes("rows not consecutive")));
});
