---
name: llm-quota-routing
description: "Diagnose and design quota-aware LLM fallback routing across multiple providers. Use when an agent/cron/router keeps failing with 429, 400, 502, when free-tier quota runs out, when a fallback chain 'walks all tiers and dies', when scheduling agent work around daily quota resets, or when a weak fallback model silently degrades output quality. Triggers: 429, rate limit, RPD, RPM, TPM, quota exhausted, fallback chain, model failover, circuit breaker, capped retry, 9router, combo, free tier, dead tier, reasoning_content 400, cross-provider schema."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), distilled with Claude (Opus) from a model-fleet post-mortem, 3–10 Jul 2026
license: MIT
---

# LLM Quota Routing — make a fleet of free models actually work

A long fallback chain is **not** resilience. A long chain whose tiers are quietly dead is a quota
incinerator: every call pays N tiers × M retries before it reaches a live model, and that live model is
usually the worst one.

Use this skill to **diagnose** why a model fleet fails, **redesign** its chain, and **schedule** agent work
into the hours when quota is actually alive.

## Core laws (in order of importance)

1. **"429" is not a diagnosis.** The failure an agent reports always comes from the **last tier**. The error
   you see is the bottom model's error, not the root cause. Always break it down per tier, per status.
   Proxies and routers wrap upstream 429/502 as HTTP 400 — never trust the outermost HTTP code.

2. **Separate the four failures that look identical to the user:**

   | Symptom | Cause | Cure |
   |---|---|---|
   | 429 `RESOURCE_EXHAUSTED` | daily/per-minute quota exhausted | schedule into the reset window, reduce cadence |
   | 400 `invalid_request_error` | **schema incompatibility**, permanent | drop that tier, or clean the payload |
   | 502 / timeout | upstream endpoint misbehaving | retry with jitter, circuit-break |
   | succeeds but the output is garbage | the fallback model is too weak | **quality gate**: better to fail loudly |

3. **Quota is a bucket per model, not per account.** One dry model does not mean the whole provider is dry.
   Send a small probe per model before crossing a tier off. Conversely, a small TPM can reject one large
   agentic request while RPD is still plentiful — that model may still serve as a cushion for small calls only.

4. **Quota resets have a time zone, and it dictates your work schedule.** Do not schedule an agent during
   hours that are guaranteed dry. See `references/provider-limits.md`.

5. **Retries must be capped.** Exponential backoff plus jitter, honouring `Retry-After` / `x-ratelimit-*`.
   Immediate retries with no pause turn one 429 into a storm that sustains the very overload causing it.
   Once the cap is spent: **report clearly**, do not loop forever.

6. **Dead tiers must be removed, not tolerated.** Every dead tier adds latency and retries to every single
   agent step. Circuit breaker: N consecutive failures on one tier → open the circuit for 60s, close it
   gradually. For **permanent** failures (400 schema, 404 model), remove it from the chain — do not
   circuit-break it.

7. **Quality gate beats availability.** For work that **writes to persistent storage** (a knowledge base,
   memory, documents, a database), a weak fallback model is more dangerous than a failure. Subtly broken
   output — mixed languages, invented numbers, a file overwritten wholesale — only surfaces days later.
   **Rule:** a chain for persistent-write work contains only models you trust. When they are exhausted,
   **fail loudly**. Long chains are fine for read/analysis work whose output is discarded.

8. **Routers hide provider identity — and that causes bugs.** Agent clients often adapt their payload based
   on `base_url` or the provider name (per-vendor quirks). Behind a proxy everything looks like a single
   host, so quirk detection fails. Real case: see "Cross-provider schema contamination" below.

## Cross-provider schema contamination (the most expensive trap)

Reasoning models (Gemini 2.5, DeepSeek, Kimi, nemotron) return `reasoning_content` on assistant messages.
The client stores it in conversation history. On the next turn that history is **replayed** to whichever
model happens to serve. Providers that do not recognise the field reject it:

```
400 invalid_request_error: 'messages.7' : for 'role:assistant' the following must be satisfied
[('messages.7' : property 'reasoning_content' is unsupported)]
```

The consequence: that tier returns a **permanent 400 from the third turn of every run onward**, which looks
like "the provider is down" while it is perfectly healthy. Some providers, meanwhile, **require** this field
to be echoed back (DeepSeek V4 thinking, Kimi/Moonshot, Xiaomi MiMo) — so it cannot simply be stripped globally.

**The right fixes, in order of preference:**
1. Clean the payload **at the router**, per destination provider: strip `reasoning_content`/`reasoning` for
   providers that reject it, keep it for providers that require it. The router knows the real destination;
   the client does not.
2. If you cannot touch the router: do not mix reasoning and non-reasoning models in one chain for
   multi-turn conversations.
3. Cheapest of all: remove the rejecting tier from the chain.

Check first whether your client has host-based quirk detection (`base_url_host_matches`) — if it does,
routing through a proxy disables it.

## Diagnosis playbook (30 minutes, no guessing)

Run `scripts/router-health.sh` if your target is 9router. If not, follow the same sequence:

1. **Tally per model per status** from the *router's* logs, not the agent's. A model at 100% errors is a
   permanent-failure suspect. A model with mixed errors and successes is rate-limited.
2. **Read the raw upstream error**, not the wrapped one. In 9router: column `data` → `providerResponse.error`.
   The code inside it (400 vs 429) determines the cure.
3. **Map the successful hours.** Group successful runs by hour. The success peak is the quota reset window.
   That is your schedule.
4. **Compute the run economics.** `failed runs/day × tiers × retries` = wasted calls. If 90% of runs fail,
   the cadence is too tight: the daily quota is gone in the first two hours and the rest is just noise.
5. **Inspect output quality, not just status.** Open 2–3 artifacts written by "successful" runs. A stray
   foreign language, duplicated paragraphs, a file overwritten entirely — all mean the serving model is too
   weak, however green the status was.

## Rules for designing a chain

- **Chain length ≤ 3** for persistent-write work. Order: best quality → same-class backup → last still-adequate
  backup. Not "everything that is free".
- Every tier must pass three tests: **alive** (ping), **compatible** (schema), **adequate** (output quality).
- Work cadence follows real capacity, not hope. Measure `successes/day` over a week, then schedule that many
  plus 1–2 backup attempts, all inside the reset window.
- One attempt per window beats four attempts that eat each other's RPM.
- Record per run: serving model, status, tokens. Without that, "the agent is dumb" and "the provider is down"
  are indistinguishable.

## References

- `references/provider-limits.md` — free-tier limits and reset hours for Gemini, Groq, OpenRouter and others.
- `references/diagnosis-playbook.md` — ready-to-run SQL/shell commands for 9router + hermes-agent.
- `scripts/router-health.sh` — per-model per-status tally, last raw error, map of successful hours.

## Sources

- Google — [Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) (accessed 2026-07-10)
- OpenRouter — [API rate limits](https://openrouter.ai/docs/api-reference/limits) (accessed 2026-07-10)
- Groq — [API error codes](https://console.groq.com/docs/errors) · [Reasoning](https://console.groq.com/docs/reasoning) (accessed 2026-07-10)
- NousResearch/hermes-agent — [issue #11089: Groq `reasoning_content` unsupported](https://github.com/NousResearch/hermes-agent/issues/11089) (accessed 2026-07-10)
- vercel/ai — [issue #8056: Groq models receiving unsupported `reasoning` field](https://github.com/vercel/ai/issues/8056) (accessed 2026-07-10)
- Maxim AI — [Retries, fallbacks, and circuit breakers in LLM apps](https://www.getmaxim.ai/articles/retries-fallbacks-and-circuit-breakers-in-llm-apps-a-production-guide/) (accessed 2026-07-10)
- TrueFoundry — [Rate limiting AI agents: 3-layer gateway](https://www.truefoundry.com/blog/rate-limiting-ai-agents-preventing-llm-api-exhaustion) (accessed 2026-07-10)
- Field evidence: a post-mortem of the Hermes agent's model fleet on a single self-hosted mini-PC,
  3–10 Jul 2026 (218 failed runs, 24 successes).
