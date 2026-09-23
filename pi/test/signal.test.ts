import assert from "node:assert/strict";
import test from "node:test";
import { HANDOFF_PREFIXES, isHandoffSignal } from "../src/signal.ts";

test("signal: detects the 'Implement here' handoff", () => {
  assert.equal(
    isHandoffSignal({
      source: "extension",
      text: "Plan mode is now disabled. Full tool access is restored. Implement this proposed plan now:\n\n1. do x",
    }),
    true,
  );
});

test("signal: detects the clear-on-start handoff", () => {
  assert.equal(isHandoffSignal({ source: "extension", text: "Implement the plan." }), true);
});

test("signal: detects the 'Start fresh' handoff", () => {
  assert.equal(
    isHandoffSignal({
      source: "extension",
      text: "A previous agent produced the plan below to accomplish the user's task. Implement the plan in a fresh context.",
    }),
    true,
  );
});

test("signal: ignores source 'user'", () => {
  assert.equal(isHandoffSignal({ source: "user", text: "Implement the plan." }), false);
});

test("signal: ignores source 'interactive' and 'rpc'", () => {
  assert.equal(isHandoffSignal({ source: "interactive", text: "Implement the plan." }), false);
  assert.equal(isHandoffSignal({ source: "rpc", text: "Implement the plan." }), false);
});

test("signal: ignores unrelated extension-sourced text", () => {
  assert.equal(isHandoffSignal({ source: "extension", text: "Something else entirely." }), false);
});

test("signal: prefix must anchor at the start, not just appear anywhere", () => {
  assert.equal(
    isHandoffSignal({ source: "extension", text: "Note: Implement the plan. (not really)" }),
    false,
  );
});

test("signal: all three documented prefixes are exported", () => {
  assert.equal(HANDOFF_PREFIXES.length, 3);
});
