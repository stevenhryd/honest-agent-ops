---
name: weak-model-delegation
description: "Hand work to a cheaper, weaker or local model (free-tier cloud, 9router combo, llama.cpp/Qwen, small OSS models) so the result can be judged by machine instead of re-read by hand. Use when delegating bulk/boilerplate generation, when a delegated result comes back wrapped in prose or truncated mid-JSON, when designing tool schemas or agent tool catalogs, or when deciding what may and may not be delegated. Triggers: delegation, delegate to cheaper model, 9router, cc-main, local Qwen, local LLM output, structured output, JSON mode, strict schema, additionalProperties, GBNF, grammar-constrained decoding, guided decoding, xgrammar, json_schema, tool schema, function calling, tool catalog too large, defer_loading, tool search, model returns prose around JSON, truncated output, schema drift, output contract."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), distilled with Claude (Opus) from llama.cpp/vLLM/OpenAI/Anthropic primary sources + field notes 1 Sep 2026
license: MIT
---

# Weak Model Delegation — a contract, not a favour

Delegating to a cheap model only saves anything if the result can be **judged without a human reading it**.
If every result has to be read to know whether it is right, the saving is zero — the expensive tokens you
avoided get spent again on repair.

> **Parent law:** delegation is a contract a machine can enforce. Write down how the result will be judged
> *first*; only then send the task. If the acceptance criteria cannot be executed, do not delegate.

## When to use

The moment these words appear: delegation · free model · `cc-main` · local Qwen · "to save tokens" ·
JSON output from an LLM · tool schema · too many tools in the catalog · "the output got cut off" ·
"why did it wrap the answer in an explanation".

How it differs from its neighbours: **`llm-quota-routing`** answers *which model is still alive*; this
skill answers *how to make its answer directly usable*. **`tool-calling-architect`** teaches how to write
a single tool; this skill is about **enforcing a contract** on a weak model.

## 1. Two failure modes — separate them, the cures differ

| Mode | Shape | Cure |
|---|---|---|
| **Selection error** | The model picks the wrong tool/file/task, calls too many, or skips the needed one | Shrink the catalogue (§4), sharpen names and descriptions |
| **Invocation error** | Right tool/task, wrong **arguments**: missing field, wrong type, mangled date format | Strict schema + enforcement at the decoding layer (§2) |

The second does more damage to the final result, and is precisely the one people keep trying to fix with
prompting. **A tidy schema beats a clever prompt almost every time** — a prompt is a request, a schema is
a constraint.

## 2. The contract-enforcement ladder (strongest first)

Climb as high as the backend supports. Do not stop at the bottom rung.

| # | Method | Guarantee | Available in |
|---|---|---|---|
| 1 | **Grammar-constrained decoding** (GBNF / xgrammar) | Tokens outside the grammar **cannot be emitted** | llama.cpp, vLLM — the local-model path |
| 2 | **Strict schema** | Fields and types exactly as the JSON Schema says | Anthropic (`strict: true`), OpenAI-compatible APIs |
| 3 | **JSON mode** | Valid JSON syntax — the fields can still be wrong | Most providers |
| 4 | **Prompting alone** ("reply with JSON only") | None | Everything — and this is the one that fails |

### 2a. Local Qwen (llama.cpp) — rung 1

Source: llama.cpp `grammars/README.md`.

```bash
# grammar directly
llama-cli -m MODEL --grammar-file schema.gbnf -p 'PROMPT'
llama-cli -m MODEL -j '{"type":"object","properties":{...}}'   # -j / --json: JSON Schema → GBNF automatically
```

`llama-server` accepts `grammar` or `json_schema` in the body of the completion endpoint, and
`response_format` on `/chat/completions` — so an already-running `:8080` endpoint can be forced to comply
**without changing anything on the client side**. Important: *"The JSON schema is only used to constrain
the model output and is not injected into the prompt"* — the model is never told the schema, so **still
describe the output shape in the prompt**; the grammar only prevents deviation.

GBNF limitations you must know (all documented):
- `additionalProperties` **defaults to `false`** for performance.
- `prefixItems` is broken (use `items`); nested `$ref` is broken; `uniqueItems`/`contains`/`not`/conditionals
  are unsupported.
- Numeric bounds apply only to `"type": "integer"` — **not** to `number`.
- `pattern` must start with `^` and end with `$`; remote schema references are unsupported in the C++ version.
- Never write `x? x? x?…` — sampling becomes very slow; use `x{0,N}`.

### 2b. vLLM — rung 1

Five forms: `choice` · `regex` · `json` · `grammar` (EBNF) · `structural_tag`. Backends `xgrammar` /
`guidance`, plus an `auto` mode. **The `guided_json`/`guided_regex` fields were removed in v0.12.0** — use
the `structured_outputs` parameter. One trap that hits this exact use case: on reasoning models such as
**Qwen3-Coder, structured output is off unless you enable it** with
`--structured-outputs-config.enable_in_reasoning=True`.

### 2c. Claude / Anthropic — rung 2

- **Strict tool use:** `strict: true` is a **top-level field on the tool definition** (next to
  `name`/`description`/`input_schema`) — **not** on `tool_choice`. The schema must carry
  `additionalProperties: false` plus `required`. The result: `tool_use.input` is guaranteed to validate.
- **Structured outputs:** `output_config: {format: {...}}` on `messages.create()`. The older
  `output_format` parameter is deprecated. Easiest path: `client.messages.parse()` — it validates
  automatically.
- Not compatible with programmatic tool calling, `disable_parallel_tool_use`, a forced `tool_choice`,
  or MCP tools.

### 2d. OpenAI-compatible APIs (9router → free Sonnet, and similar) — rung 2

Source: OpenAI Structured Outputs documentation.

- `"additionalProperties": false` is mandatory, and **every property must be `required`**.
- Optional fields are expressed through a nullable type: `"type": ["string", "null"]` — not by removing
  them from `required`.
- Supported: string/number/boolean/array/object, `enum`, recursive `$ref`, nested objects and arrays.
- **Truncation** surfaces as `status: "incomplete"` plus `incomplete_details.reason: "max_output_tokens"` —
  not as an error. A safety refusal arrives as a separate `type: "refusal"` block, so it can be detected
  programmatically.

## 3. When the output is not JSON (the most common case: file contents)

"Write the contents of file X" cannot be guaranteed by a schema. What *can* be enforced:

1. **One artifact per call.** Never ask for two files at once — a weak model will merge them, add headings,
   or truncate the second.
2. **A sentinel frame** that cannot occur in the content, e.g. `<<<BEGIN>>>` … `<<<END>>>`. Extract what
   lies between them mechanically. A missing closing sentinel means **truncated**, not finished — that is
   truncation detection with no access to `finish_reason` required.
3. **Executable acceptance criteria**, written before you send: `node --check`, `python -m json.tool`,
   `tsc --noEmit`, `bash -n`, a minimum line count, or an existing test. If no command can pass verdict,
   the task **is not a delegation candidate**.
4. **A system prompt that closes the prose loophole:** "output ONLY the file contents, no code fences, no
   explanation, no preamble." Still verify — this is a request, not a guarantee.

Quick verdict before the result is used:

```bash
~/.claude/skills/weak-model-delegation/scripts/contract-check.sh <file> [--json|--sentinel] [--min-lines N]
```

## 4. Tool catalogue size is not taste, it is accuracy

Evidence — Repantis, Gawde, Singh & Blackwell II, *"How Many Tools Should an LLM Agent See? A
Chance-Corrected Answer"*, [arXiv:2605.24660](https://arxiv.org/abs/2605.24660), 23 May 2026. Three
tool-selection benchmarks, registries from 20 to 3,251 tools:

- On **BFCL (370 tools)**, a learned adaptive-depth policy presenting **~7 tools on average** nearly matches
  the coverage of showing 50 (**90.3% vs 90.8%**).
- On **ToolBench (3,251 tools)**, a fixed shortlist of 5 wins on aggregate coverage (64.7% vs 61.9%) but
  **finds nothing** on hard queries where the correct tool ranks 6th–20th; the adaptive agent finds
  **16.7%** of those by searching deeper.
- Downstream validation with **Claude Sonnet 4.6**: shorter adaptive lists raised tool-selection accuracy
  to **93.1%** from **87.1%** when always shown 5 tools — widening to **76.8% vs 60.9%** on medium-difficulty
  queries where the right tool is present but not ranked first.

The cause is mechanical: the model's attention spreads across many similar names, and it then either
invents a tool name or calls the right tool with **another tool's arguments**. That is failure mode #2,
triggered by #1.

**Anthropic's official answer** for large catalogues is not "choose them yourself" but the built-in tool
search: declare `tool_search_tool_regex_20251119` or `tool_search_tool_bm25_20251119`, then mark the other
tools `defer_loading: true`. One trap: **never defer everything** — the search tool itself must not carry
`defer_loading`, and at least one tool must be non-deferred, otherwise the API rejects the request with
`400 All tools have defer_loading set`.

Rule of thumb: **≤ 10–20 active tools** per context; beyond that use deferred loading, not hope.

## 5. Parallel, sequential, and how to return failures

- **Parallel when independent, sequential when dependent** (A's output feeds B, or both mutate the same state).
- A single assistant message may contain many `tool_use` blocks. Return **all** `tool_result` blocks in
  **one user message**. Splitting them across several messages silently trains the model to stop calling
  in parallel.
- A failed tool is **still returned**, with `is_error: true` — never dropped. Its message should be a
  structured failure string ("field `date` must be ISO 8601, got '5 July'") so the model can repair itself
  without starting over. Do not throw a raw exception back.

## 6. Retry: change strategy, do not resend

A validation error is a **signal**, not an accident:

1. Attempt 1 fails validation → send **the error message itself** back to the model (a correction loop;
   libraries such as Instructor automate this).
2. Attempt 2 → **shrink the schema** or split it into two calls. A bigger schema means more chances to be wrong.
3. Attempt 3 → escalate to a stronger model, or do it yourself.
4. Cap at 2–3 attempts, written down. Resending an identical prompt to the same model is not a retry, it is
   a prayer.

For quota-driven failures (429/400/502) and fallback chains: `llm-quota-routing`.
For scheduled jobs that report success while producing nothing: `honest-automation`.

## 7. What may be delegated

| May | Must not |
|---|---|
| Boilerplate from a complete specification; files from a template | Architecture decisions, cross-file wiring |
| Translation/reformatting that has a mechanical checker | Anything whose correctness can only be judged by reading it |
| Structured extraction under a strict schema | Root-cause debugging |
| Large volumes of uniform output | Micro-edits (orchestration overhead exceeds the saving) |

You remain the **final reviewer**: a delegated result passes the acceptance criteria before it is used.

## 8. Do not inherit stale recipes

Old notes (including agents' own learning notes) still recommend patterns the API now **rejects**:

- ❌ `anthropic-beta: interleaved-thinking-2025-05-14` + `thinking={"type":"enabled","budget_tokens":N}`.
  ✅ Now `thinking: {type: "adaptive"}`; `budget_tokens` is **answered with a 400** on Fable 5, Fable 5.1,
  Opus 5, 4.8 and 4.7, and Sonnet 5, and interleaved thinking turns itself on with no beta header from 4.6
  onward. (Haiku 4.5 and older models still take `budget_tokens`.)
- ❌ `output_format` → ✅ `output_config: {format: {...}}`.
- ❌ `guided_json` in vLLM → ✅ `structured_outputs` (removed in v0.12.0).
- ❌ Prefilling the assistant message to force a format → **400** on Fable 5, Fable 5.1, Opus 5/4.8/4.7/4.6,
  and Sonnet 5/4.6. Use structured outputs instead.

General rule: before copying an API recipe from any note more than a month old, check it against the
official documentation (for Claude: the `claude-api` skill).

## References

- `references/backend-recipes.md` — full syntax per backend (llama.cpp, vLLM, Anthropic, OpenAI-compatible)
  plus a table of documented limitations.
- `references/contract-patterns.md` — delegation prompt templates, sentinel framing, acceptance criteria
  per artifact type.
- `scripts/contract-check.sh` — mechanical verdict on a delegated result (wrapper prose, truncation,
  invalid JSON, multiple artifacts).
