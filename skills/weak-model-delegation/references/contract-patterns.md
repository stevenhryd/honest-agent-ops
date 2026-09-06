# Delegation contract templates

The correct order is: **write the acceptance criteria → write the prompt → send → pass verdict.** If you
cannot complete the first step, the task is not a delegation candidate.

---

## General frame

```
DELEGATION CONTRACT
  artifact  : one file / one JSON object  (NEVER two)
  shape     : <JSON schema | GBNF | sentinel frame>
  criteria  : <the command that judges it, exit 0 = accept>
  ceiling   : 2 attempts, a different strategy each time
  recipient : me (final reviewer) — the result is not used before it passes the criteria
```

---

## Pattern 1 — Structured extraction (the strongest)

Use whenever the output can be expressed as an object.

```jsonc
// schema — note the three things strict mode requires
{
  "type": "object",
  "additionalProperties": false,          // 1. close off stray fields
  "required": ["code", "name", "price"],  // 2. EVERY property goes in required
  "properties": {
    "code":  {"type": "string", "description": "Item code in the target ERP, e.g. 'BRG-0012'"},
    "name":  {"type": "string"},
    "price": {"type": ["number", "null"]} // 3. optional = nullable, not removed from required
  }
}
```

Schema-design rules for weak models:
- **As small as possible.** A bigger schema means more chances to be wrong. Split it into two calls if needed.
- **Every parameter description states the format plus a concrete example**: `"ISO 8601 date, e.g. '2026-03-15'"`.
  This is the single largest reducer of argument errors.
- **`enum` for closed sets**, never a free-form string.
- **Function and field names should express intent**: `fetch_order_v2` beats `order`. The version also lets
  you A/B-test description changes without breaking existing callers.

Acceptance criteria: `python -m json.tool` plus schema validation (`jsonschema`, `pydantic`).

---

## Pattern 2 — File contents (cannot be schema'd)

```
Write the complete contents of the file <path>.

Output ONLY the file contents, between the two markers below.
No code fences, no explanation, no opening or closing sentence.

<<<BEGIN>>>
(file contents here)
<<<END>>>
```

Why a sentinel rather than a code fence ``` : code fences also appear **inside** the content (READMEs,
documentation), so they cannot serve as a boundary. Pick a sentinel that cannot occur in the content.

Mechanical verdict:
- `<<<BEGIN>>>` missing → the model wrapped it in prose → reject.
- `<<<END>>>` missing → **truncated**, not finished → reject; this is truncation detection that needs no
  access to `finish_reason`.
- Text outside the sentinel pair → discard it, never treat it as content.
- Two sentinel pairs → the model produced two artifacts → reject, redo one at a time.

The acceptance criteria then follow the file type: `node --check`, `bash -n`, `tsc --noEmit`,
`python -m py_compile`, `psql -f … --dry-run`, or an existing test.

---

## Pattern 3 — Line-by-line transformation

For translation, reformatting, renumbering. The strongest contract here is not a schema but a
**countable invariant**:

```
- the output line count MUST equal the input line count
- the first column of every line must not change
- no extra blank lines
```

Verdict: `wc -l` on both sides plus `cut -f1 | diff`. A countable invariant beats eyeballing for large
output — and large output is exactly why you delegated.

---

## Pattern 4 — Many files

Don't. One call = one artifact. For N files, N calls, repeating the same contract. A weak model asked for
many files will merge their contents, invent its own separator headings, or truncate the last file without
saying so.

If N is large and the files share a pattern, send a **template plus a table of values**, and ask for one
file per call from one row of that table — rather than asking the model to invent the variations itself.

---

## System-prompt sentences that prove necessary

```
Output ONLY <artifact>. No explanation, no code fences, no preamble.
If you cannot determine something, write UNKNOWN as that value — do not invent one.
Do not summarize, do not truncate. If the content is long, still write it in full.
```

The second line matters: without an explicit escape hatch, a weak model **fills in a guess** rather than
admitting it does not know — and a well-formatted guess passes every syntax check.

---

## What decides whether a task may be delegated at all

One question: **which command will pass verdict on the result?**

- There is an answer → delegate.
- The answer is "I'll read it first" → do it yourself. Reading a delegated result costs the same expensive
  tokens as doing the work, plus the risk of an error you do not see.
