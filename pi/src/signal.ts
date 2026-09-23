/**
 * The handoff signal: pi.on("input") firing with event.source === "extension"
 * and text starting with one of plan-mode's implementation-handoff strings.
 * See ../probe.md section 1 (SIGNAL) for how these three prefixes were found.
 */

export const HANDOFF_PREFIXES = [
  "Plan mode is now disabled. Full tool access is restored. Implement this proposed plan now:",
  "Implement the plan.",
  "A previous agent produced the plan below",
] as const;

export interface InputLikeEvent {
  source?: string;
  text?: string;
}

/** True when this input event is a plan-mode implementation handoff. */
export function isHandoffSignal(event: InputLikeEvent): boolean {
  if (event.source !== "extension") return false;
  const text = event.text ?? "";
  return HANDOFF_PREFIXES.some((prefix) => text.startsWith(prefix));
}
