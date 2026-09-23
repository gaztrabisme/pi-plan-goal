# Run ledger — 2026-09-22 plan-goal

| Unit | Lane | Verdict | Acceptance | Notes |
|---|---|---|---|---|
| lane check | Codex | CLOSED | `codex exec` probe | Spark: "not supported when using Codex with a ChatGPT account"; Astra, Luna: "usage limit … try again at Sep 27th, 2026 5:18 PM" |
| fork | — | decided forward | — | U1 rerouted Codex → DeepSeek (peer strength, multi-file). U5 review rerouted to Claude agent so reviewer ≠ author lane. |
| fork | — | decided forward | — | U0a/U0b (Claude agents) and U6 (GLM) share the project dir but write disjoint subdirs (pi/, claude-code/, bin/+spec/). |
| U6 goal-block spec + validator | GLM | PASS | coordinator ran all six checks: example 0, goal file 0, too-long 1 ("4001/4000"), no-check 1, gap 1, stdin 0 | 374 s, 146k tokens |
| U0a pi probe | Claude agent (sonnet) | PASS | coordinator: SIGNAL/DISPATCH lines present; pi-run/probe-result.json shows goal-state status "active" after cross-extension /goal | DISPATCH proven on real headless pi + oMLX |
| lane check | DeepSeek | CLOSED | U1 dispatch | "API Error: 402 Insufficient Balance" |
| fork | — | decided forward | — | U1 rerouted DeepSeek → Claude agent (sonnet). Both multi-file lanes closed; Claude agent is the plan's fallback. |
| outage | all remote lanes | BLOCKED | `curl https://api.anthropic.com` → exit 6; `dig @127.0.2.2` empty, `dig @1.1.1.1` resolves | Local DNS resolver 127.0.2.2 (Cloudflare WARP) stopped answering ~03:58Z 2026-09-23. Killed U1 and U0b agents (ENOTFOUND) and U3 GLM run (cli_error after 4770 s). |
| U3 Codex | GLM | FAIL (partial) | coordinator ran codex/uat.sh: 5 cases FAIL (b–e), f–h PASS; script exits 0 despite failures (defect) | partial files kept for the rerun |
| U1 pi bridge | Claude agent | INTERRUPTED | — | src/gate.ts, goal-block.ts, signal.ts written; no package.json/tests yet |
| U0b CC probe | Claude agent | INTERRUPTED | probe.md absent | sandbox evidence kept in claude-code/probe-sandbox/ |
| resume | — | — | curl api.anthropic.com 404, api.z.ai 301 | DNS recovered; U0b, U1 redispatched to Claude agents from partial files, U3 rerun on GLM |
| lane check | Codex | OPEN | `codex exec -m gpt-5.6-luna -c model_reasoning_effort=xhigh` → OK | Gary: "Codex is back use Luna 6 at extra high". gpt-6-luna → "not supported when using Codex with a ChatGPT account"; used gpt-5.6-luna |
| fork | — | decided forward | — | U2 GLM → Codex Luna xhigh; U5 Claude agent → Codex Luna xhigh (≠ U1 author lane); U4 → oMLX Qwen3.8-Flash, 1 stream (Gary offered) |
| U0b CC probe | Claude agent (sonnet), rerun | PASS | coordinator: APPROVE/REJECT/STOP present; filePath and stop_hook_active recorded | reject fires no PostToolUse; both Stop block forms work |
| lane check | Codex | OPEN | `codex update` 0.153.4 → 0.156.1; `codex exec -m gpt-6-luna -c model_reasoning_effort=xhigh` → OK | Gary: "Luna 6 is released so I think we need to update Codex". U2 left running on gpt-5.6-luna (old binary, unaffected); U5 review uses gpt-6-luna |
| U3 Codex | GLM rerun | PASS | coordinator: codex/uat.sh exit 0, 8 PASS; PLAN_GOAL_MAX_BLOCKS=0 → exit 1 | root cause: `python3 -` read the heredoc as the program, so hook stdin JSON was never seen. Correction: the earlier ledger line "exits 0 despite failures" was a coordinator misread (exit status of `tail`, not the script). Guard refused the compound verification; coordinator ran it. |
| U2 Claude Code plugin | Codex gpt-5.6-luna xhigh | PASS | coordinator: claude-code/uat.sh exit 0, 10/10 PASS (incl. exit 2 + "4001", "/goal Execute plan", loop cap 8, broken-copy self-test); `claude plugin validate claude-code` ✔ | install verified in isolated CLAUDE_CONFIG_DIR: `/plugin marketplace add <path>/claude-code`, `/plugin install plan-goal@pi-plan-goal` |
