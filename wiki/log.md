# Run ledger — 2026-09-22 plan-goal

| Unit | Lane | Verdict | Acceptance | Notes |
|---|---|---|---|---|
| lane check | Codex | CLOSED | `codex exec` probe | Spark: "not supported when using Codex with a ChatGPT account"; Astra, Luna: "usage limit … try again at Sep 27th, 2026 5:18 PM" |
| fork | — | decided forward | — | U1 rerouted Codex → DeepSeek (peer strength, multi-file). U5 review rerouted to Claude agent so reviewer ≠ author lane. |
| fork | — | decided forward | — | U0a/U0b (Claude agents) and U6 (GLM) share the project dir but write disjoint subdirs (pi/, claude-code/, bin/+spec/). |
| U6 goal-block spec + validator | GLM | PASS | coordinator ran all six checks: example 0, goal file 0, too-long 1 ("4001/4000"), no-check 1, gap 1, stdin 0 | 374 s, 146k tokens |
