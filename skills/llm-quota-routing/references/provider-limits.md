# Free-tier limits and reset hours (checked 10 Jul 2026)

All reset hours are converted to **WIB (UTC+7)** — the time zone of the machine where these measurements
were taken. Adjust for yours. These numbers change: always verify against the official documentation
before turning one into a hard decision.

## Reset hours (what actually dictates your cron schedule)

| Provider | Daily reset | = WIB | Notes |
|---|---|---|---|
| OpenRouter (`:free`) | midnight UTC | **07:00** | counted per "current UTC day" |
| Gemini (free tier) | midnight Pacific | **14:00** (PDT) / 15:00 (PST) | RPD resets at midnight PT |
| Groq (free) | rolling window | — | per-minute/per-day limits, not a synchronized reset |
| Antigravity via 9router | individual quota, resets ~83 h | — | the error message states the exact time remaining |

**Consequence:** 20:00–07:00 WIB is a dead zone if the fleet contains only OpenRouter and Gemini.
The most fertile windows: **07:00–09:00** (OpenRouter fresh) and **14:00–17:00** (Gemini fresh).

## Per-model limits

### Gemini (free tier, per project — not per API key)
| Model | RPM | TPM | RPD |
|---|---|---|---|
| gemini-2.5-flash | 10 | 250,000 | 250 |
| gemini-2.5-flash-lite | 15 | 250,000 | 1,000 |

An RPM of 10 is easy to breach with an agentic loop firing in bursts. Error: `429 RESOURCE_EXHAUSTED`,
`generate_content_free_tier_requests`.

### OpenRouter (`:free` variants)
- **20 requests/minute** across all `:free` models.
- **50 requests/day** if you have never bought credit; **1,000/day** once you have bought ≥ $10.
- Different models have different upstream limits → spreading load across models is legitimate.
- Upstream rate limits surface as `429 "Provider returned error"` with `metadata.raw` containing
  "temporarily rate-limited upstream".

> **50/day is small.** A single agentic run can consume 15–30 calls. That means 2 runs/day, then dry.

### Groq (free)
- Limits are per model (llama-3.3-70b-versatile ≠ llama-3.1-8b-instant). One being dry does not mean the
  other is.
- 8b-instant: large RPD but **small TPM** → a large agentic prompt can be rejected while the daily quota is
  untouched. Good as a cushion for small calls, bad as the server of a full run.
- **Rejects `reasoning_content` on assistant messages** → a permanent 400 in any multi-turn conversation
  that a reasoning model has previously served. See SKILL.md.

## Models proven dead in this setup (do not re-add)

| Model | Symptom | Test date |
|---|---|---|
| `gemini/gemini-2.0-flash-lite` | 429 quota-0 from the very first request | 3 Jul 2026 |
| `gemini/gemma-3-27b-it` | 404 through 9router | 3 Jul 2026 |
| `gemini/gemini-2.0-flash` | 429 | before 3 Jul 2026 |
| `groq/llama-3.3-70b-versatile` | 400 `reasoning_content` unsupported (not quota) | 10 Jul 2026 |
| `groq/llama-3.1-8b-instant` | same | 10 Jul 2026 |

## Models that are alive but NOT fit to write

| Model | Problem |
|---|---|
| `openrouter/nvidia/nemotron-3-super-120b-a12b:free` | widely available, but its Indonesian output is contaminated with Italian/German/Vietnamese words, it invents statistics, and it overwrites whole files instead of editing part of one |
| `openrouter/qwen/qwen3-coder:free` | a code model; poor prose plus frequent upstream 429s |

Both are acceptable tiers for **read/analysis** work, never for **persistent-write** work.

## Sources

- https://ai.google.dev/gemini-api/docs/rate-limits
- https://openrouter.ai/docs/api-reference/limits
- https://console.groq.com/docs/errors
- Direct measurement: `~/.9router/db/data.sqlite` (table `requestDetails`), 9–10 Jul 2026.
