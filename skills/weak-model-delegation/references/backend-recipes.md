# Resep per backend — sintaks & batasan terdokumentasi

Diverifikasi 1 Sep 2026 dari dokumentasi resmi masing-masing. Kalau satu baris di sini bertabrakan
dengan ingatan, dokumen resminya yang menang — API ini berubah cepat.

---

## llama.cpp (Qwen lokal, `local-llm`, port :8080)

Sumber: `grammars/README.md` di repo llama.cpp.

### Memberi tata bahasa

```bash
llama-cli -m MODEL --grammar-file grammars/skema.gbnf -p 'PROMPT'
llama-cli -m MODEL --grammar 'root ::= "ya" | "tidak"' -p 'PROMPT'
llama-cli -m MODEL -j '{"type":"object","properties":{"nama":{"type":"string"}}}'   # -j / --json
```

`llama-server`:
- endpoint completion → field body `grammar` **atau** `json_schema`
- `/chat/completions` → field `response_format`
- ahead-of-time: `examples/json_schema_to_grammar.py`

> "The JSON schema is only used to constrain the model output and is **not injected into the prompt**."

Artinya prompt tetap harus menjelaskan bentuk yang diinginkan; grammar hanya melarang penyimpangan.

### Sintaks GBNF secukupnya

| Unsur | Bentuk |
|---|---|
| Non-terminal | huruf kecil berstrip: `move`, `nilai-uang` |
| Terminal | `"1"` atau rentang `[1-9]`, negasi `[^\n]` |
| Urutan | `"1. " move " " move "\n"` |
| Alternatif | `move ::= pion \| bukan-pion \| rokade` |
| Grup | `(x \| y)` |
| Pengulangan | `*` `+` `?` `{m}` `{m,n}` |
| Token khusus | `<think>`, `<[1000]>` |
| Komentar | `#` |

Aturan `root` menentukan bentuk keluaran keseluruhan. Unicode didukung penuh.

### Batasan yang terdokumentasi (jangan ditemukan sendiri lewat trial-error)

- `additionalProperties` **default `false`** demi performa.
- `prefixItems` **rusak** — pakai `items`.
- `$ref` **bersarang rusak**; referensi skema jarak jauh tak didukung di versi C++.
- Batasan numerik hanya untuk `"type": "integer"`, **bukan** `"number"`.
- `pattern` wajib diawali `^` dan diakhiri `$`.
- Tak ada `uniqueItems`, `contains`, `not`, maupun konstruksi kondisional.
- **Performa:** `x? x? x? …` bikin sampling sangat lambat; tulis `x{0,N}`.

---

## vLLM

Sumber: dokumentasi Structured Outputs vLLM.

Lima bentuk: `choice` · `regex` · `json` (JSON Schema) · `grammar` (EBNF bebas-konteks) ·
`structural_tag` (JSON Schema di dalam tag tertentu).

Backend: `xgrammar`, `guidance` (dua-duanya regex gaya Rust), plus mode `auto` yang memilih sendiri
berdasarkan isi permintaan. `outlines` dan `lm-format-enforcer` disebut sebagai backend lain dengan
dialek regex berbeda (`lm-format-enforcer` memakai `re` Python).

**Dua hal yang paling sering menjatuhkan:**
1. `guided_json` / `guided_regex` / dkk. **dihapus di v0.12.0** → pakai parameter `structured_outputs`.
2. Pada model ber-reasoning (mis. **Qwen3 Coder**) structured output **nonaktif** kecuali dinyalakan:
   `--structured-outputs-config.enable_in_reasoning=True`.

Tersedia lewat endpoint OpenAI-compatible maupun inferensi offline via `SamplingParams`.

---

## Anthropic / Claude

Sumber: skill `claude-api` (dokumentasi resmi, cache 2026-06-24). Untuk kode per bahasa, panggil skill
itu — jangan menebak nama SDK dari bentuk cURL.

### Strict tool use

- `strict: true` = **field top-level pada definisi tool**, sebelah `name` / `description` /
  `input_schema`. **Bukan** di `tool_choice`.
- Skema wajib `additionalProperties: false` + `required`.
- Jaminan: `tool_use.input` lolos validasi persis.
- Go: `Strict: anthropic.Bool(true)` + `additionalProperties` lewat `InputSchema.ExtraFields`.
  Java: `.strict(true)` + `.putAdditionalProperty("additionalProperties", JsonValue.from(false))`.
- **Tak kompatibel** dengan programmatic tool calling, `disable_parallel_tool_use`, `tool_choice`
  yang dipaksa, dan tool MCP.

### Structured outputs

- `output_config: {format: {...}}` pada `messages.create()`. `output_format` yang lama **usang**.
- Jalur yang dianjurkan: `client.messages.parse()` — validasi otomatis terhadap skema.
- **Tak kompatibel dengan citations** (`citations: {enabled: true}` pada blok dokumen) → 400.

### Tool search untuk katalog besar

- Deklarasikan `tool_search_tool_regex_20251119` **atau** `tool_search_tool_bm25_20251119`.
- Tandai tool lain `defer_loading: true`.
- **Jangan defer semuanya**: tool pencari tak boleh `defer_loading`, dan minimal satu tool harus
  non-deferred → kalau tidak, `400 All tools have defer_loading set`.

### Paralel & kegagalan

- Satu pesan asisten boleh berisi banyak blok `tool_use`; jalankan bersamaan, lalu kembalikan
  **semua** `tool_result` dalam **satu** pesan user. Memecahnya melatih model berhenti paralel.
- Tool gagal → `tool_result` dengan `is_error: true`. Jangan dibuang.

### Truncation

Jangan pelit `max_tokens`: kena batas = keluaran terpotong di tengah dan harus diulang. Default sehat:
±16.000 untuk non-streaming, ±64.000 untuk streaming. Untuk `max_tokens` sangat besar (hingga 128K pada
model kini) SDK **mewajibkan streaming** agar tak kena timeout HTTP.

---

## API OpenAI-compatible (9router → Sonnet gratis, LM lain)

Sumber: dokumentasi Structured Outputs OpenAI.

**Syarat mode strict**
- `"additionalProperties": false` wajib.
- **Semua properti harus `required`.**
- Field opsional dibuat lewat tipe nullable — `"type": ["string", "null"]` — bukan dengan
  menghapusnya dari `required`.

**Didukung:** string · number · boolean · array · object · `enum` · `$ref` rekursif · objek/larik bersarang.

**Kondisi tepi yang harus dideteksi program (bukan exception):**
| Kondisi | Tanda |
|---|---|
| Terpotong | `status: "incomplete"` + `incomplete_details.reason: "max_output_tokens"` |
| Penolakan keamanan | blok konten `type: "refusal"` terpisah |
| Diblokir filter | `incomplete_details.reason: "content_filter"` |

Ketiganya **tidak** menghasilkan JSON yang sesuai skema. Cek dulu sebelum mem-parse.

**Catatan 9router:** history yang membawa `reasoning_content` dari penyedia lama ditolak `HTTP 400` oleh
penyedia yang lebih ketat. Itu wilayah `llm-quota-routing`, bukan skema — jangan salah diagnosis sebagai
masalah structured output.
