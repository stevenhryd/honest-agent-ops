---
name: honest-automation
description: "Design and audit unattended work — cron, systemd timers, PM2 processes, scheduled agents, watchdogs, refresh/sync scripts — so that a green status cannot mean zero work done. Use when a job reports ok/healthy but nothing changed, when adding any scheduled or background task, when a dashboard/monitor is healthy while output stopped, or when deciding what a job must prove before it may claim success. Triggers: cron, crontab, systemd timer, OnFailure, PM2, watchdog, heartbeat, dead man's switch, scheduled agent, background job, silent failure, no-op run, empty run, stale artifact, absent metric, monitoring blind spot, 'last_status=ok but nothing happened', 'job says ok tapi tak ada hasil', hijau tapi nol."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), distilled with Claude (Opus) from real incidents 26 Aug – 1 Sep 2026 + primary sources
license: MIT
---

# Honest Automation — make "ok" mean something

Unattended work has one characteristic disease: **its status is written by the actor.**
The job decides for itself that it succeeded, then writes `ok`. Nothing ever compares that claim
against the world. The result is not a false alarm — it is **wrong silence**: months of green, zero output.

> **Parent law:** status is written by the actor, evidence is written by the world. If both come from
> the same source, the status is worth nothing.

This skill does two things: **pass verdict** on jobs already running, and **design** new jobs that cannot lie.

## When to use

Reach for this skill the moment these words appear: cron, systemd timer, PM2, watchdog, scheduled agent,
periodic sync, refresh, backup, "runs every night" — or the moment someone says
**"it says it ran, so where is the output?"**

How it differs from `verification-before-completion`: that skill is about **me** not claiming completion
without evidence inside a session. This skill is about **machines** running when nobody is there.

## 1. The failure class: green but empty

Five shapes, every one of which actually happened in the system this skill came from:

| Shape | Real example | What lies |
|---|---|---|
| **Impossible step reported done** | Job `hermes-peta` was told to run `graphify --update` 77×; `execute_code` is blocked in cron by design. `graphify-out/` had been empty since 2 Jul, `last_status=ok` every single time | The job does not know its instruction is impossible |
| **Intent announced, writing never happened** | 31 Aug 16:00/18:00/20:00 `mentor-reflection`: "I will now merge…" then stopped. No file changed after 14:02. All three logged `ok` | A sentence of intent is read as a result |
| **Health indicator on the wrong layer** | fxbot: PM2 green, log advancing every 20 minutes, watchdog HEALTHY — while the probe had been stuck for 70 minutes; telemetry dead 5 weeks, unnoticed | The indicator measures a different layer |
| **Verdict command uses the wrong instrument** | `pgrep -c terminal64.exe` always returns 0 under Wine → twice declared "MT5 is down" and wrote that down as fact | The measuring instrument itself was never tested |
| **The auditor marks itself as failed** | An audit wrapper passed `exit 1` ("findings exist") straight through → the scheduler marked the job `error` → the next day's audit read "cron failed" as an *additional* gap → red forever | Two different signals stacked into one channel |

The shared trait: **not one of these is detectable by process monitoring.** Every process really did run.

## 2. Why standard tooling does not catch them

This is not a configuration oversight — it is genuinely outside those tools' reach:

- **systemd `OnFailure=`** fires only when a unit enters the **`failed`** state (`systemd.unit(5)`, since v201).
  A job that `exit 0`s while doing nothing never enters `failed`, so `OnFailure=` **mechanically cannot**
  catch it. `OnSuccess=` fires instead (the unit goes `inactive`).
- **Exit codes** report whether the process finished, not whether the work happened. `exit 0` means
  "I did not crash", not "I produced something".
- **cron** dumps stdout to unread mail (or `/dev/null`); it has no concept of a result.
- **PM2 `online`** means the process exists. It says nothing at all about progress.
- **The Google SRE Workbook** is right to alert on the *outcome* users experience rather than on causes —
  but the *Alerting on SLOs* chapter is entirely about error budgets and burn rate; the
  **"healthy but producing nothing" case is not covered**. Do not look for the answer there; it has to be designed.

Only one kind of signal catches this: **the absence of output that should exist.**
Prometheus calls it `absent_over_time()` — "useful for alerting on when no time series exist for a given
metric name and label combination **for a certain amount of time**". The dead-man switch model
(healthchecks.io) is the same idea: the system **stays quiet while pings arrive on time**, and **fires
precisely when a ping does not arrive**. Use `/start` plus a success ping so the gap between "started"
and "finished" is measured too — that catches a job that starts and then evaporates, not just one that
never starts.

## 3. Four laws

### L1 — Capability preflight: never schedule an impossible step

Before a step goes into an unattended job, answer: **can this step succeed in that environment, with no
human present?** If not, remove the step — do not hope it will fail loudly.

Impossible steps proven in the field:

| Step | Why it is impossible unattended |
|---|---|
| `execute_code` in Hermes cron | Blocked by design — no human is there to approve it |
| `pkexec …` from an SSH session | Needs a graphical polkit agent; none in SSH → use `sudo -S` |
| `sudo` directly from Claude Code | No tty |
| Anything that needs LLM quota | Quota exhausted = job dead, not job slow |

**Quick test:** run the step once in exactly the same environment (same user, session, permissions, no tty).
If it cannot be demonstrated even once by hand, it does not deserve a schedule.

Design consequence: **work that needs a shell does not belong in an LLM-driven job.** A script mode
(`--no-agent`) costs zero tokens, cannot hit quota, and does not trip tool blocks.

### L2 — An output contract that can be falsified

Every job must state, **written down in its own file**, one sentence:

```
SUCCESS := <artifact> grew/changed since <when>, observable via <command>
```

Without that sentence, "success" is just a feeling. The rules:

- **Artifacts, not activity.** A new log line is not an artifact — a log advancing while work has stopped
  is failure shape #3 itself. An artifact is a file whose contents someone else consumes, a new row in a
  database, a commit, an output file.
- **Staleness is measured from CONTENT, not age.** "Graph older than 7 days" produced five false alarms
  on 26 Aug. The correct form: "a source file is **newer** than its graph". Compare two real things;
  never compare one thing against the calendar.
- **Falsifiable.** A contract that cannot fail measures nothing. If you cannot name one state of the world
  that would make this contract fire, the contract is empty.
- **Empty is legitimate, but must be deliberate.** A job that legitimately does not always produce output
  (e.g. "report only if there are findings") gets the contract: *empty stdout = quiet = no findings*.
  Distinguish that from *did not run* — that belongs to the heartbeat (L3), not to the artifact check.

### L3 — One channel, one meaning

Three distinct signals; never stack them:

| Signal | Channel | Meaning |
|---|---|---|
| Findings exist / output produced | **stdout** | content = report it · empty = stay quiet |
| The tool itself is broken | **exit ≠ 0** | it could not run at all |
| The job never ran | **absence of a ping/artifact** | detected from outside, by someone else |

Violating this creates a feedback loop: an audit wrapper passes `exit 1` through as "findings exist" →
the scheduler marks `error` → tomorrow's audit reads "job failed" as an additional gap → red forever.
A reporting job's wrapper **always exits 0**; findings go to stdout.

And most important of all: **the auditor is not the actor.** The same job must never both do the work and
judge it. The verdict has to come from a separate process that only reads the world.

### L4 — A ceiling, and a different strategy per attempt

Being stuck is neither a reason to go silent nor a licence to retry forever:

- Each attempt uses a **different strategy** (switch model, narrow the scope, split the task) — not the
  same request resent. Repeating an identical request at an overloaded server makes things worse.
- The **ceiling is written explicitly** in code or configuration (attempt count · time limit · token
  limit), never implied, so it can be audited and tuned.
- **Non-idempotent** actions (send, transfer, post) must not be retried automatically without an
  idempotency key.
- Out of strategies → **report what was tried and where it stopped**, do not go silent.

## 4. How to pass verdict on a running job

The order matters — do not start with the logs.

1. **Ask for its contract.** Which artifact should have grown? If nobody can name one, that is finding
   number one: a job with no contract.
2. **Compare run times against artifact times.**
   ```bash
   ~/.claude/skills/honest-automation/scripts/audit-job.sh <name> \
       --evidence '<glob>' --since '<ISO or "6 hours ago">' [--min 1]
   ```
   A run that happened after the last artifact is an **empty run**. That is a verdict, not a suspicion.
3. **Read the run's final answer, not its status.** For LLM-driven jobs: a last sentence in the form of
   *intent* ("I will now…", "starting by reading…") followed by a stop is an empty run even when the
   status is `ok`. Code printed as text (`print(...)`) is the signature of a blocked execution tool
   falling back to prose — an L1 violation.
4. **Test the measuring instrument once.** Before passing verdict through a shell command, prove the
   command returns what you think it does (`pgrep` vs `pgrep -f` under Wine). An untested instrument is
   a guess wearing numbers.
5. **Count yield, not runs.** `270 runs` means nothing; `81 artifacts from 270 runs` means something.

## 5. How to install a job that cannot lie

The minimum template — valid for cron, systemd timers and scheduled agents alike:

```bash
#!/usr/bin/env bash
# CONTRACT: success := a new file exists in ~/output/ since the previous run.
# stdout has content = findings · exit != 0 = the tool is broken (NOT "findings exist").
set -uo pipefail

do_work() { : "the actual work goes here"; }

before=$(find ~/output -type f -newermt '-1 day' | wc -l)
do_work || { printf 'TOOL BROKEN: do_work() could not run\n'; exit 2; }
after=$(find ~/output -type f -newermt '-1 day' | wc -l)

if [ "$after" -le "$before" ]; then
  printf 'EMPTY RUN: do_work() finished without adding a file to ~/output\n'
fi
exit 0
```

Three things make it honest: the contract is written on the first line · the artifact delta is measured
before and after · an empty run **reports via stdout** while still exiting 0.

For the outer layer (the job never ran at all), install one of these:

- **Prometheus**: `absent_over_time(<job_metric>[<period + grace>])` → alert.
- **Dead-man switch** (healthchecks.io or anything equivalent): ping `/start` at the beginning, ping
  success at the end; grace time bounds the maximum gap between them.
- **Without a network**: one separate auditor job that reads the artifact mtimes of every other job,
  running less often than the jobs it watches. Reference pattern: a `--no-agent` step (zero tokens) plus
  a separately scheduled audit script that compares artifacts, not statuses.

## 6. Traps

- **An auditor that counts itself.** If the auditor appears in the list it audits, one of its failures
  becomes two findings tomorrow. Exclude it explicitly.
- **An ignore list with no reasons.** Files that are "intentionally empty" (`.audit-ignore` and friends)
  must carry **a reason per line**. Without the reason it is not a decision, it is a hidden gap.
- **Absolute age thresholds.** "> N days = stale" always produces false alarms on things that legitimately
  change rarely. Compare content against content.
- **Confusing "identical" with "current".** `corpus == graph` only proves two copies match; both can be
  equally stale. A third check is required: **the source is newer than the corpus**.
- **Adding schedule slots to paper over empty runs.** 4×/day where 3 produce nothing is worse than
  1×/day that finishes: it burns quota and hides yield behind run count.
- **Alarms nobody reads.** The outbound channel (stdout to the scheduler, a notification, a report file)
  has to be one a human actually looks at; otherwise honesty changes nothing.

## References

- `references/failure-catalog.md` — the full catalogue of failure shapes plus how to recognise each in
  logs and output.
- `references/primary-sources.md` — primary-source quotations (systemd, Prometheus, healthchecks,
  SRE Workbook) and precisely what each one does **not** guarantee.
- `scripts/audit-job.sh` — verdict of "working / empty run / never ran" from artifact evidence.
