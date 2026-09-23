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

test("isMutatingBash: newline-separated read-only commands pass", () => {
  assert.equal(isMutatingBash("git status\ngit log -1\ncat file.txt"), false);
});

test("isMutatingBash: a lone trailing newline doesn't block an otherwise read-only command", () => {
  assert.equal(isMutatingBash("cat file.txt\n"), false);
});

// H1 (research/review.md): the allowlist accepted mutating find/git diff
// options and didn't split on newlines, so an armed agent could edit files
// before writing a goal. Each case below is a bypass from that finding.
test("isMutatingBash: H1 bypasses are all blocked", () => {
  for (const command of [
    // find options that mutate or run further commands
    "find . -type f -delete",
    "find . -name '*.txt' -exec rm {} \\;",
    "find . -name '*.txt' -execdir rm {} \\;",
    "find . -name '*.txt' -ok rm {} \\;",
    "find . -name '*.txt' -okdir rm {} \\;",
    "find . -fprint out.txt",
    "find . -fprint0 out.txt",
    "find . -fprintf out.txt '%p\\n'",
    "find . -fls out.txt",
    // git diff options that write files or shell out
    "git diff --output=out.txt",
    "git diff --output out.txt",
    "git diff --ext-diff",
    "git diff --textconv",
    // git global flags that change what git runs
    "git -c core.pager=cat log",
    "git --exec-path=/tmp/evil log",
    "git log --exec-path=/tmp/evil",
    // newline used to smuggle a second, unparsed statement
    "cat /dev/null\nrm -f marker",
    "git status\nrm -rf /tmp/x",
    // redirection variants
    "cat a.txt <> out.txt",
    "cat a.txt | tee out.txt",
    // process/command substitution
    "cat <(rm -rf /tmp/x)",
    "cat `rm -rf /tmp/x`",
    // shells, wrappers, and privilege/backgrounding tools that can run
    // arbitrary further commands
    "env rm -rf /tmp/x",
    "xargs rm -rf /tmp/x",
    "find . -type f | xargs rm",
    "sh -c 'rm -rf /tmp/x'",
    "bash -c 'rm -rf /tmp/x'",
    "nohup rm -rf /tmp/x",
    "sudo rm -rf /tmp/x",
  ]) {
    const decision = gateToolCall("bash", { command });
    assert.equal(decision.block, true, `expected "${command}" to be blocked`);
  }
});
