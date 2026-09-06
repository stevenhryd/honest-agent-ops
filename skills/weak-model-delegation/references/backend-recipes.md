# Per-backend recipes — syntax and documented limitations

Verified 1 Sep 2026 against each project's official documentation. If a line here conflicts with your
recollection, the official document wins — these APIs move fast.

---

## llama.cpp (local Qwen, `local-llm`, port :8080)

Source: `grammars/README.md` in the llama.cpp repository.

### Supplying a grammar

```bash
llama-cli -m MODEL --grammar-file grammars/schema.gbnf -p 'PROMPT'
llama-cli -m MODEL --grammar 'root ::= "yes" | "no"' -p 'PROMPT'
llama-cli -m MODEL -j '{"type":"object","properties":{"name":{"type":"string"}}}'   # -j / --json
```

`llama-server`:
- completion endpoint → body field `grammar` **or** `json_schema`
- `/chat/completions` → field `response_format`
- ahead of time: `examples/json_schema_to_grammar.py`

> "The JSON schema is only used to constrain the model output and is **not injected into the prompt**."

Which means the prompt must still describe the shape you want; the grammar only forbids deviation.

### Enough GBNF syntax

| Element | Form |
|---|---|
| Non-terminal | lowercase with hyphens: `move`, `money-value` |
| Terminal | `"1"` or a range `[1-9]`, negation `[^\n]` |
| Sequence | `"1. " move " " move "\n"` |
| Alternation | `move ::= pawn \| non-pawn \| castling` |
| Group | `(x \| y)` |
| Repetition | `*` `+` `?` `{m}` `{m,n}` |
| Special token | `<think>`, `<[1000]>` |
| Comment | `#` |

The `root` rule defines the overall output shape. Unicode is fully supported.

### Documented limitations (do not rediscover these by trial and error)

- `additionalProperties` **defaults to `false`** for performance.
- `prefixItems` is **broken** — use `items`.
- **Nested `$ref` is broken**; remote schema references are unsupported in the C++ version.
- Numeric bounds apply only to `"type": "integer"`, **not** `"number"`.
- `pattern` must start with `^` and end with `$`.
- No `uniqueItems`, `contains`, `not`, or conditional constructs.
- **Performance:** `x? x? x? …` makes sampling very slow; write `x{0,N}`.

---

## vLLM

Source: the vLLM Structured Outputs documentation.

Five forms: `choice` · `regex` · `json` (JSON Schema) · `grammar` (context-free EBNF) ·
`structural_tag` (a JSON Schema inside a particular tag).

Backends: `xgrammar`, `guidance` (both Rust-style regex), plus an `auto` mode that picks one based on the
request contents. `outlines` and `lm-format-enforcer` are named as alternative backends with different
regex dialects (`lm-format-enforcer` uses Python's `re`).

**The two things that trip people up most:**
1. `guided_json` / `guided_regex` and friends were **removed in v0.12.0** → use the `structured_outputs`
   parameter.
2. On reasoning models (e.g. **Qwen3 Coder**) structured output is **off** unless enabled:
   `--structured-outputs-config.enable_in_reasoning=True`.

Available through the OpenAI-compatible endpoint and through offline inference via `SamplingParams`.

---

## Anthropic / Claude

Source: the `claude-api` skill (official documentation, cached 2026-06-24). For per-language code, invoke
that skill — do not guess SDK names from the shape of a cURL example.

### Strict tool use

- `strict: true` is a **top-level field on the tool definition**, next to `name` / `description` /
  `input_schema`. **Not** on `tool_choice`.
- The schema requires `additionalProperties: false` plus `required`.
- Guarantee: `tool_use.input` validates exactly.
- Go: `Strict: anthropic.Bool(true)` plus `additionalProperties` via `InputSchema.ExtraFields`.
  Java: `.strict(true)` plus `.putAdditionalProperty("additionalProperties", JsonValue.from(false))`.
- **Not compatible** with programmatic tool calling, `disable_parallel_tool_use`, a forced `tool_choice`,
  or MCP tools.

### Structured outputs

- `output_config: {format: {...}}` on `messages.create()`. The older `output_format` is **deprecated**.
- Recommended path: `client.messages.parse()` — automatic validation against the schema.
- **Not compatible with citations** (`citations: {enabled: true}` on a document block) → 400.

### Tool search for large catalogues

- Declare `tool_search_tool_regex_20251119` **or** `tool_search_tool_bm25_20251119`.
- Mark the other tools `defer_loading: true`.
- **Never defer everything**: the search tool must not carry `defer_loading`, and at least one tool must be
  non-deferred — otherwise `400 All tools have defer_loading set`.

### Parallelism and failures

- One assistant message may contain many `tool_use` blocks; run them concurrently, then return **all**
  `tool_result` blocks in **one** user message. Splitting them trains the model to stop going parallel.
- A failed tool → `tool_result` with `is_error: true`. Never drop it.

### Truncation

Do not lowball `max_tokens`: hitting the cap truncates the output mid-thought and forces a retry. Healthy
defaults: ~16,000 for non-streaming, ~64,000 for streaming. For very large `max_tokens` (up to 128K on
current models) the SDKs **require streaming** to avoid HTTP timeouts.

---

## OpenAI-compatible APIs (9router → free Sonnet, other LMs)

Source: the OpenAI Structured Outputs documentation.

**Strict-mode requirements**
- `"additionalProperties": false` is mandatory.
- **Every property must be `required`.**
- Optional fields are expressed through a nullable type — `"type": ["string", "null"]` — not by removing
  them from `required`.

**Supported:** string · number · boolean · array · object · `enum` · recursive `$ref` · nested objects and arrays.

**Edge conditions your code must detect (they are not exceptions):**
| Condition | Marker |
|---|---|
| Truncated | `status: "incomplete"` + `incomplete_details.reason: "max_output_tokens"` |
| Safety refusal | a separate content block of `type: "refusal"` |
| Filter-blocked | `incomplete_details.reason: "content_filter"` |

None of the three yields schema-conforming JSON. Check for them before parsing.

**9router note:** history carrying `reasoning_content` from a previous provider is rejected with `HTTP 400`
by stricter providers. That is `llm-quota-routing` territory, not a schema problem — do not misdiagnose it
as a structured-output issue.
