# Catalogue of "green but empty" failures — signatures and verdicts

Use this when inspecting a job that is already running. Look for the **signature**, not for an error
message — this failure class does not produce errors.

---

## F1 · Impossible step reported done

**Signature**
- The prompt or script asks for something the environment forbids (blocked tool, needs a tty, needs approval).
- The target file never existed, or has not changed since the job was created.
- The status is always `ok`, never once `error` — that perfect stability is itself the suspicious part.

**Example** `hermes-peta` was told to run `graphify --update` across 77 runs; `execute_code` is blocked in
cron by design; `graphify-out/` had been empty since 2 Jul.

**Verdict** Run the step by hand in exactly the same environment. If it cannot succeed even once, the step
is removed from the job — not scheduled more often.

---

## F2 · Intent announced, writing never happened

**Signature (typical of LLM-driven jobs)**
- The final answer is a statement of **intent**, not a result: "I will now merge…", "Starting by reading
  X and Y.", "After that I will update Z."
- The answer is cut off mid-sentence ("I found").
- Code is printed as text (`print(new_content)`) instead of executed → the execution tool was blocked and
  the model fell back to prose. This is F1 disguised as F2.
- The target file is unchanged even though the run reported it would change it.

**Example** 31 Aug 2026, three consecutive `mentor-reflection` runs (16:00 · 18:00 · 20:00) — all `ok`, and
not one file in `~/.hermes/knowledge/`, `.archive/`, or the vault changed after 14:02.

**Verdict** The newest artifact's `mtime` is earlier than the run's start time. No need to read the content.

---

## F3 · Health indicator on the wrong layer

**Signature**
- What is monitored: process alive, log advancing, watchdog green. What was actually asked: is the work
  progressing.
- The watchdog travels a different path from the real work, so it does not break when the work breaks.
- The log advances every N minutes with identical content each time.

**Example** fxbot — this pattern appeared **8 times**: telemetry dead for 5 weeks unnoticed; the probe stuck
for 70 minutes while PM2 was green, the log advanced every 20 minutes, and the watchdog read HEALTHY.

**Verdict** Compare the indicator against **the output that should be growing** (new telemetry rows, new
positions, new tickets). Output not growing while the indicator is green means **the indicator is wrong**,
not that the system is healthy.

---

## F4 · A measuring instrument that was never tested

**Signature**
- The verdict rests on a single shell command that was never tried against a positive case.
- The command returns 0 or empty, and that absence is then recorded as fact.

**Example** `pgrep -c terminal64.exe` always returns 0 for processes under Wine (it needs `pgrep -f`) →
twice declared "MT5 is down" and wrote it into a commit message as fact.

**Verdict** Run the instrument while the condition you are looking for **actually holds**. If it does not
fire there, its numbers are worthless. An untested instrument is a guess wearing numbers.

---

## F5 · The auditor marks itself as failed (feedback loop)

**Signature**
- A wrapper passes through an `exit≠0` that actually means "findings exist".
- The scheduler marks the job `error`; tomorrow's auditor reads "job failed" as an additional finding.
- The finding count rises monotonically while nothing is actually getting worse.

**Example** 28 Aug 2026 — an audit wrapper passed `exit 1` straight through → red forever until the two
signals were separated.

**Verdict and cure** The wrapper **always exits 0**; findings go to stdout; `exit>1` is reserved for
"the tool is broken". The auditor is excluded from the list it audits, explicitly.

---

## F6 · Staleness measured against the calendar

**Signature**
- The rule has the form "older than N days = stale".
- Alarms fire on files that legitimately change rarely and are perfectly correct.

**Example** 26 Aug 2026 — an absolute age threshold on a graph produced **5 false alarms**.

**Verdict** Replace it with a content-against-content comparison: "a **source** is newer than its
**derivative**".

---

## F7 · Two copies match, both are stale

**Signature**
- The check has the form `A == B` between two derivatives (corpus vs graph, cache vs index).
- No check touches the original **source** at all.

**Example** 28 Aug 2026 — 18 source files were newer than `sources/`, while the `corpus-vs-graph` check
reported them identical and the audit stayed quiet.

**Verdict** Add the third check: **source → corpus**. A derivation chain must be checked from its
furthest upstream end.

---

## F8 · Schedule increased to paper over empty runs

**Signature**
- Frequency rises with no fix to the underlying cause.
- Yield (artifacts ÷ runs) falls while run count rises.

**Example** `mentor-reflection` at 4×/day produced roughly 1 note/day — 3 runs burning quota every day,
with the large run count hiding the yield.

**Verdict** Count **yield**, not runs. Lower the frequency until every run has a contract that is actually met.
