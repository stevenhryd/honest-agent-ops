# Honest Agent Ops

**Three Claude Code skills for work nobody is watching.**

Unattended work has one characteristic disease: **its status is written by the thing being judged.**
The job decides for itself that it succeeded, writes `ok`, and nothing ever compares that claim
against the world. The result is not a false alarm — it is *wrong silence*: months of green, zero output.

> **Parent law:** status is written by the actor, evidence is written by the world.
> If both come from the same source, the status is worth nothing.

These skills were distilled from real post-mortems on a self-hosted 24/7 agent stack, and every
external claim in them is cited to a primary source — with the **limits of that guarantee** stated
explicitly, which is usually the part that gets left out.

---

## The three skills

### `honest-automation`
Design and audit unattended work — cron, systemd timers, PM2 processes, scheduled agents, watchdogs,
refresh/sync scripts — so that a green status cannot mean zero work done.

Covers five documented failure shapes (impossible step reported done · intent sentence read as result ·
health indicator measuring the wrong layer · verdict command using the wrong instrument · auditor
flagging itself as failed), why standard tooling structurally cannot catch them, and four laws for
building jobs that cannot lie.

Key mechanical fact it is built on: **`OnFailure=` fires only on the `failed` state.** A unit that
`exit 0`s without doing anything goes to `inactive`, so `OnFailure=` can never catch an empty run —
and `OnSuccess=` fires instead. No systemd setting changes this. Empty-run detection has to come from
artifact comparison, outside systemd.

Ships with `scripts/audit-job.sh` — verdict by artifact, not by exit code.

### `weak-model-delegation`
Hand work to a cheaper, weaker or local model so the result can be **judged by machine instead of
re-read by hand**. Delegation only saves anything if you never have to read the output to know whether
it is right.

Covers the enforcement ladder (grammar-constrained decoding → strict schema → JSON mode → prompting,
which is the rung that fails), backend recipes for llama.cpp GBNF, vLLM structured outputs, Anthropic
strict tools and OpenAI-compatible APIs, plus the documented GBNF limitations that bite in practice
(`additionalProperties` defaults to `false`; `prefixItems` and nested `$ref` are broken; numeric bounds
apply to `integer` but not `number`; Qwen3-style reasoning models need
`--structured-outputs-config.enable_in_reasoning=True` on vLLM or structured output is silently off).

Ships with `scripts/contract-check.sh` — an executable acceptance test for delegated output.

### `llm-quota-routing`
Diagnose and design quota-aware fallback routing across providers. A long fallback chain is **not**
resilience: if each tier is quietly dead, every call pays N tiers × M retries before reaching the one
live model, and that model is usually the worst one.

Core discipline: **"429" is not a diagnosis.** The error you see comes from the *last* tier, and proxies
wrap upstream 429/502 as HTTP 400 — so never trust the outermost status code. Separate the four
look-alike failures (429 quota · 400 permanent schema incompatibility · 502 upstream · degraded output),
because the cure differs for each. A dead tier is removed; a rate-limited tier is *rescheduled*.

Ships with `scripts/router-health.sh` — per-model, per-status health snapshot from request logs.

---

## Install

```bash
# in Claude Code
/plugin marketplace add stevenhryd/honest-agent-ops
/plugin install honest-agent-ops@honest-agent-ops
```

Or drop the skills straight in:

```bash
git clone https://github.com/stevenhryd/honest-agent-ops
cp -r honest-agent-ops/skills/* ~/.claude/skills/
```

Each skill is self-contained: `SKILL.md` + `scripts/` + `references/`. No runtime dependency on this
repo, on each other, or on any particular model provider.

## Use

The skills auto-trigger on their descriptions. You can also invoke them by name:

| Say this | Get this |
|---|---|
| "this cron says ok but nothing changed" | `honest-automation` |
| "I'm adding a nightly sync job" | `honest-automation` |
| "the free model keeps returning prose around my JSON" | `weak-model-delegation` |
| "delegate this bulk generation to a cheap model" | `weak-model-delegation` |
| "my fallback chain walks every tier and dies" | `llm-quota-routing` |
| "429 from everything, which tier is actually alive?" | `llm-quota-routing` |

## How they relate

```
llm-quota-routing        → which model is still alive?
weak-model-delegation    → how do I make its answer usable without reading it?
honest-automation        → how do I know the job that used it actually produced something?
```

## A note on style

The prose is deliberately dense — these files are read by a model under a token budget, so they favour a
table over a paragraph and a mechanism over an adjective. A few trigger phrases and the wrapper-prose
detector in `contract-check.sh` accept Indonesian as well as English, since a delegated model may answer
in either; everything else is English.

## Sources

Every external claim is cited to a primary source, and each source note states **what it does not
guarantee**. See `skills/honest-automation/references/primary-sources.md` for the pattern —
`systemd.unit(5)`, PromQL `absent_over_time()`, healthchecks.io, and Google SRE Workbook, each with the
boundary of its guarantee written out.

Numbers without a traceable path to their origin are not used at all. That rule is enforced in the
text: where a widely-quoted figure survives, its actual paper is named.

## Contributing

Field reports are the most valuable contribution: a green-but-empty failure this catalog does not
cover, with enough detail to reproduce the *shape* of it. See `CONTRIBUTING.md`.

## License

MIT © 2026 Steven Hariyadi
