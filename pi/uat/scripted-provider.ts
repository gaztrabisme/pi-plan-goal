/**
 * Deterministic scripted provider + harness for uat/headless.sh.
 *
 * Registers a fake model whose "responses" are a fixed script driven purely
 * by the most recent tool result in the transcript - not by turn counting.
 * That makes it robust to extra turns pi-goal injects on its own (its /goal
 * prompt after activation), which would desync a naive step counter.
 *
 * The handoff is injected from pi.on("agent_start") via pi.sendUserMessage()
 * - any extension calling that sets event.source === "extension" (see
 * ../probe.md section 1), so this does not need to load pi-plan-mode itself.
 * It is NOT sent from a registered command handler on the initial CLI
 * prompt: empirically, pi.sendUserMessage() called as the very first message
 * a fresh session ever sees (no session, or session with zero prior turns)
 * crashes @narumitw/pi-goal with "turn_end could not resolve the persisted
 * assistant entry ID" (reproduces with pi-goal loaded and no plan-goal
 * extension at all, so it is not something this bridge causes). Running one
 * harmless turn first (the CLI's own initial prompt, "go") gives the session
 * a real first turn, and only the *second* message - the handoff, injected
 * mid-run from agent_start - is extension-sourced. That sidesteps the crash.
 */

import { readFileSync } from "node:fs";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { type AssistantMessage, createAssistantMessageEventStream } from "@earendil-works/pi-ai";

const HANDOFF_MARKER = "Headless UAT";
const HANDOFF_TEXT =
  "Plan mode is now disabled. Full tool access is restored. Implement this proposed plan now:\n\n" +
  `Execute plan "${HANDOFF_MARKER}" (uat/headless.sh). Goal rows:\n` +
  "1 probe: test -f output/marker.txt";

function readFixture(path: string): string {
  return readFileSync(path, "utf8");
}

function messageText(content: unknown): string {
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((block) => (block && typeof block === "object" && "text" in block ? String((block as { text: unknown }).text) : ""))
      .join("\n");
  }
  return "";
}

export default function scriptedProviderHarness(pi: ExtensionAPI) {
  const tooLongBlock = readFixture(process.env.PLAN_GOAL_TOO_LONG_FIXTURE ?? "");
  const exampleBlock = readFixture(process.env.PLAN_GOAL_EXAMPLE_FIXTURE ?? "");
  let handoffSent = false;

  pi.registerProvider("scripted", {
    baseUrl: "http://unused.invalid",
    apiKey: "unused",
    api: "openai-completions",
    models: [
      {
        id: "scripted-1",
        name: "scripted-1",
        reasoning: false,
        input: ["text"],
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 },
        contextWindow: 128000,
        maxTokens: 8192,
      },
    ],
    streamSimple(model, context) {
      const stream = createAssistantMessageEventStream();

      (async () => {
        const output: AssistantMessage = {
          role: "assistant",
          content: [],
          api: model.api,
          provider: model.provider,
          model: model.id,
          usage: {
            input: 0,
            output: 0,
            cacheRead: 0,
            cacheWrite: 0,
            totalTokens: 0,
            cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0, total: 0 },
          },
          stopReason: "pending",
          timestamp: Date.now(),
        };
        stream.push({ type: "start", partial: output });

        // Find the most recent tool result in the transcript, regardless of
        // any extra turns interleaved by pi-goal's own activation prompt.
        let lastToolResult: { toolName: string; isError: boolean } | undefined;
        for (let i = context.messages.length - 1; i >= 0; i--) {
          const message = context.messages[i] as { role: string; toolName?: string; isError?: boolean };
          if (message.role === "toolResult") {
            lastToolResult = { toolName: message.toolName ?? "", isError: Boolean(message.isError) };
            break;
          }
        }

        const handoffSeen = context.messages.some(
          (message) => (message as { role: string }).role === "user" && messageText((message as { content: unknown }).content).includes(HANDOFF_MARKER),
        );

        let toolCall: { name: string; arguments: Record<string, unknown> } | undefined;
        if (!lastToolResult) {
          if (handoffSeen) {
            toolCall = {
              name: "edit",
              arguments: { path: "should-not-be-written.txt", edits: [{ oldText: "a", newText: "b" }] },
            };
          }
          // else: pre-handoff warm-up turn - fall through to the plain-text reply below.
        } else if (lastToolResult.toolName === "edit" && lastToolResult.isError) {
          toolCall = { name: "write_goal", arguments: { block: tooLongBlock } };
        } else if (lastToolResult.toolName === "write_goal" && lastToolResult.isError) {
          toolCall = { name: "write_goal", arguments: { block: exampleBlock } };
        } else if (lastToolResult.toolName === "write_goal" && !lastToolResult.isError) {
          toolCall = { name: "write", arguments: { path: "output/marker.txt", content: "done\n" } };
        }

        if (toolCall) {
          output.content.push({ type: "toolCall", id: `call-${context.messages.length}`, ...toolCall });
          stream.push({ type: "toolcall_start", contentIndex: 0, partial: output });
          stream.push({ type: "toolcall_end", contentIndex: 0, toolCall: output.content[0], partial: output });
          output.stopReason = "toolCalls";
        } else {
          output.content.push({ type: "text", text: "script complete" });
          stream.push({ type: "text_start", contentIndex: 0, partial: output });
          stream.push({ type: "text_delta", contentIndex: 0, delta: "script complete", partial: output });
          stream.push({ type: "text_end", contentIndex: 0, content: "script complete", partial: output });
          output.stopReason = "endTurn";
        }

        stream.push({ type: "done", reason: output.stopReason, message: output });
        stream.end();
      })();

      return stream;
    },
  });

  pi.on("agent_start", (_event, ctx) => {
    if (handoffSent) return;
    handoffSent = true;
    if (ctx.isIdle()) {
      pi.sendUserMessage(HANDOFF_TEXT);
    } else {
      pi.sendUserMessage(HANDOFF_TEXT, { deliverAs: "steer" });
    }
  });
}
