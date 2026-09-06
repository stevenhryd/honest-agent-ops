# Primary sources — and what they do NOT guarantee

Verified 1 Sep 2026. Every line here is quoted from the source itself, not from a blog summarizing it.
The most useful part of each entry is the last one: **the limit of the guarantee**.

## systemd — `OnFailure=` / `OnSuccess=`

Source: `systemd.unit(5)`, local man page (systemd 260, Arch).

> `OnFailure=` — "A space-separated list of one or more units that are activated when this unit enters
> the **failed** state." (Added in version 201.)
>
> `OnSuccess=` — "…activated when this unit enters the **inactive** state." (Added in version 249.)

**Limit of the guarantee:** state transitions only. A unit that finishes `exit 0` without doing any work
enters `inactive`, not `failed` — so `OnFailure=` is **mechanically incapable** of catching an empty run,
and `OnSuccess=` fires instead. No systemd setting changes this; empty-run detection has to come from
artifact comparison, outside systemd.

Corollary: `SuccessExitStatus=` only widens the set of exit codes treated as success — it widens the hole
rather than closing it.

## Prometheus — `absent()` / `absent_over_time()`

Source: official PromQL documentation, *Query functions*.

> `absent(v instant-vector)` — returns an empty vector if the input vector has elements; returns a
> 1-element vector with the value `1` if the input has no elements. "Useful for alerting on when no time
> series exist for a given metric name and label combination."
>
> `absent_over_time(v range-vector)` — the range variant: `1` when **no samples at all** exist in the range.
> "…for a certain amount of time."

Example from the docs: `absent_over_time(nonexistent{job="myjob"}[1h])` → `{job="myjob"}`.

**Limit of the guarantee:** it detects the *absence of a signal*, not the *quality of a result*. A job that
keeps emitting metrics while producing nothing still passes. The metric therefore has to be an **output
metric** (artifact count, rows written), not a liveness metric (uptime, heartbeat).

## healthchecks.io — the dead man's switch model

Source: official documentation.

- The service "listens for HTTP requests (pings) from your job", **stays quiet while pings arrive on time**,
  and **fires when a ping does not arrive**.
- Three signals: a plain ping = success · `/start` = started · `/fail` = explicit failure. There is also a
  `/<exitcode>` form.
- **Grace Time** = extra time allowed before alerting. When `/start` is used, grace time doubles as the
  **maximum permitted distance between the "start" signal and the success signal**.

**Limit of the guarantee:** it proves a job *started and finished*, not that a job *produced*. The
`/start` + success pair catches a job that evaporates mid-run — exactly the "intent announced, writing
never happened" case — but an artifact contract is still needed to catch a job that finishes tidily with
nothing to show.

## Google SRE Workbook — *Alerting on SLOs*

Source: `sre.google/workbook/alerting-on-slos/`.

> "Having good SLOs that measure the reliability of your platform, **as experienced by your customers**,
> provides the highest-quality indication for when an on-call engineer should respond."

Chapter contents: burn rate against an error budget; the recommended multi-window strategy — 2% of budget
in 1 hour (page), 5% in 6 hours (page), 10% in 3 days (ticket).

**Limit of the guarantee — important:** this chapter is about services that **serve requests**. The case of
"the system looks healthy but produces no output" is **not covered**, including in its lengthy treatment of
low-traffic services. Do not cite the SRE Workbook as if it answers the empty-run problem; take the
"alert on outcomes" principle from it, and design the mechanism yourself.

## Deliberately NOT used as sources

Popular figures about agent observability (e.g. "reranking +33–40%", "caching saves 40–80%") circulate
through second-hand blogs. Some do trace back to real research — one verified example: the claim of
"85% cost savings while retaining 95% of GPT-4 quality" originates from **RouteLLM** (arXiv 2406.18665,
ICLR 2025, routing GPT-4 Turbo ↔ Mixtral 8x7B on MT Bench), not from the blogs quoting it. The rule this
skill applies: **a number with no traceable path to its origin is not used at all.**
