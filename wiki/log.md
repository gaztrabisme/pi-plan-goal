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
| U1 pi bridge | Claude agent (sonnet), rerun | PASS | coordinator: npm test 23/23; uat/headless.sh 7/7 PASS incl. goal-state "active"; uat/install.sh 6/6 PASS | deliverAs "followUp" for /goal dispatch; injected prompt 523 chars ≈131 tokens |
| U4 README | oMLX Qwen3.8-Flash (1 stream, cold load) | PASS | coordinator: grep count 15 ≥ 3; Gemini/Copilot/Cursor/opencode/Oh My Pi present; install lines match pi/uat/install.sh and marketplace.json | 566 s; guard refused compound verification, coordinator ran it |
| U5 fix H1 (pi) | Claude agent (sonnet) | PASS | coordinator: npm test 26/26, headless 0, install 0; 7 bypasses now flagged, ls/git status allowed | fix commit 381f342 |
| U5 fix H2–H4 (claude-code) | Codex gpt-6-luna xhigh | PASS | coordinator: uat 13/13 (k, l, m new), plugin validate ✔; H2 repro: redirect and find -delete denied, ls allowed | fix commit 364a507 |
| U5 fix H5–H6 (codex) | GLM | PASS | coordinator: codex/uat.sh exit 0, 11/11 (i, j, k new) | fix commit f54c31e |
| CLOSE | coordinator | 11/11 rows PASS | r1 SIGNAL/DISPATCH present · r2 APPROVE/REJECT/STOP present · r3 example 0, 4001 → 1, no-check → 1 · r4 npm test 0, headless 0 · r5 install 0 · r6 claude-code/uat.sh 0 (13/13) · r7 codex/uat.sh 0 (11/11) · r8 grep 15, five harness names · r9 review.md, 6 HIGH fixed (381f342, 364a507, f54c31e), H7 rejected D13 · r10 this ledger, D1–D15, active-work reconciled · r11 commit per wave, tree clean | Forks decided forward: Codex→DeepSeek→Claude agent for U1; U5 reviewer lane; README patched by coordinator for the two new gate hooks (one-line factual edits) |
| push | coordinator | done | `gh repo view` → https://github.com/gaztrabisme/pi-plan-goal PRIVATE main | secret scan over all commits clean before push; branch renamed master → main |
| install | coordinator | done | pi: 3 packages in ~/.pi/agent/settings.json, headless start shows write_goal · Claude Code: plan-goal@pi-plan-goal enabled (user scope) · Codex: ~/.codex/plan-goal installed, 3 hooks merged into ~/.codex/hooks.json, skill symlinked in ~/.codex/skills and ~/.agents/skills | Codex hooks untrusted until Gary runs /hooks; backups in /Users/GaryT/.config/pi-plan-goal-backup-20260923-201455 |
