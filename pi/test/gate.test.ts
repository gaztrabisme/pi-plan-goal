import assert from "node:assert/strict";
import test from "node:test";
import { gateToolCall, isMutatingBash } from "../src/gate.ts";

test("gate: edit is always blocked while armed", () => {
  const decision = gateToolCall("edit", { path: "x.ts", edits: [] });
  assert.equal(decision.block, true);
  assert.match(decision.reason ?? "", /write_goal/);
});

test("gate: write is always blocked while armed", () => {
  const decision = gateToolCall("write", { path: "x.ts", content: "y" });
  assert.equal(decision.block, true);
  assert.match(decision.reason ?? "", /write_goal/);
});

test("gate: read-only bash commands pass", () => {
  for (const command of [
    "cat file.txt",
    "ls -la",
    "grep -n foo file.txt",
    "rg foo",
    "find . -name '*.ts'",
    "git status",
    "git log -1",
    "git diff",
    "pwd",
    "wc -l file.txt",
    "head -n5 file.txt",
    "tail -n5 file.txt",
    "cat a.txt && cat b.txt",
    "cat a.txt || cat b.txt",
    "cat a.txt; cat b.txt",
    "cat a.txt | grep foo",
  ]) {
    const decision = gateToolCall("bash", { command });
    assert.equal(decision.block, false, `expected "${command}" to pass`);
  }
});

test("gate: mutating bash commands are blocked", () => {
  for (const command of [
    "rm -rf /tmp/x",
    "echo hi > out.txt",
    "echo hi >> out.txt",
    "git commit -m x",
    "git add .",
    "npm install",
    "cat a.txt && rm b.txt",
    "cat $(rm -rf /tmp/x)",
  ]) {
    const decision = gateToolCall("bash", { command });
    assert.equal(decision.block, true, `expected "${command}" to be blocked`);
    assert.match(decision.reason ?? "", /write_goal/);
  }
});

test("gate: other tools (e.g. read) are left alone", () => {
  const decision = gateToolCall("read", { path: "x.ts" });
  assert.equal(decision.block, false);
});

test("isMutatingBash: redirection is always mutating even mid-segment", () => {
  assert.equal(isMutatingBash("git status && echo hi > out.txt"), true);
});

test("isMutatingBash: command substitution is treated as mutating (can't verify statically)", () => {
  assert.equal(isMutatingBash("echo $(git status)"), true);
});
