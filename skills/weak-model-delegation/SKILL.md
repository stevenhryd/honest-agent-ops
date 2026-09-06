---
name: weak-model-delegation
description: "Hand work to a cheaper, weaker or local model (free-tier cloud, 9router combo, llama.cpp/Qwen, small OSS models) so the result can be judged by machine instead of re-read by hand. Use when delegating bulk/boilerplate generation, when a delegated result comes back wrapped in prose or truncated mid-JSON, when designing tool schemas or agent tool catalogs, or when deciding what may and may not be delegated. Triggers: delegasi, delegate to cheaper model, 9router, cc-main, Qwen lokal, local LLM output, structured output, JSON mode, strict schema, additionalProperties, GBNF, grammar-constrained decoding, guided decoding, xgrammar, json_schema, tool schema, function calling, tool catalog too large, defer_loading, tool search, model returns prose around JSON, output terpotong, schema drift, output contract."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), disuling bersama Claude (Opus) dari sumber primer llama.cpp/vLLM/OpenAI/Anthropic + catatan lapangan 1 Sep 2026
license: MIT
---

# Weak Model Delegation — kontrak, bukan permintaan tolong

Delegasi ke model murah cuma menghemat kalau hasilnya bisa **divonis tanpa dibaca manusia**. Kalau
tiap hasil harus dibaca sendiri untuk tahu benar-tidaknya, penghematannya nol — token mahal yang tadi
dihindari kembali terpakai untuk memperbaiki.

> **Hukum induk:** delegasi adalah kontrak yang bisa ditegakkan mesin. Tulis dulu cara memvonis
> hasilnya; baru kirim tugasnya. Kalau kriteria terimanya tak bisa dieksekusi, jangan didelegasikan.

## Kapan dipakai

Begitu ada kata: delegasi · model gratis · `cc-main` · Qwen lokal · "biar hemat token" · output JSON
dari LLM · skema tool · katalog tool kebanyakan · "hasilnya kepotong" · "kok dibungkus penjelasan".

Bedanya dengan tetangganya: **`llm-quota-routing`** menjawab *model mana yang masih hidup*;
skill ini menjawab *bagaimana supaya jawabannya bisa dipakai langsung*. **`tool-calling-architect`**
mengajarkan cara menulis satu tool; skill ini soal **menegakkan kontrak** pada model yang lemah.

## 1. Dua mode gagal — pisahkan, obatnya beda

| Mode | Bentuk | Obat |
|---|---|---|
| **Kesalahan seleksi** | Model memilih tool/berkas/tugas yang salah, memanggil berlebih, atau melewati yang dibutuhkan | Kecilkan katalog (§4), perjelas nama & deskripsi |
| **Kesalahan pemanggilan** | Tool/tugas benar, **argumennya** salah: field hilang, tipe meleset, format tanggal ngawur | Skema ketat + penegakan di level decoding (§2) |

Yang kedua lebih merusak hasil akhir, dan justru yang paling sering dicoba diperbaiki lewat prompt.
**Skema rapi mengalahkan prompt pintar hampir selalu** — prompt adalah imbauan, skema adalah batasan.

## 2. Tangga penegakan kontrak (terkuat di atas)

Naik setinggi yang didukung backend-nya. Jangan berhenti di anak tangga terbawah.

| # | Cara | Jaminan | Tersedia di |
|---|---|---|---|
| 1 | **Grammar-constrained decoding** (GBNF / xgrammar) | Token di luar tata bahasa **tak bisa muncul** | llama.cpp, vLLM — jalur model lokal |
| 2 | **Strict schema** | Field & tipe persis sesuai JSON Schema | Anthropic (`strict: true`), API OpenAI-compatible |
| 3 | **JSON mode** | Sintaks JSON valid — field bisa tetap salah | Kebanyakan penyedia |
| 4 | **Prompt saja** ("balas JSON saja") | Tak ada | Semua — dan ini yang gagal |

### 2a. Qwen lokal (llama.cpp) — anak tangga 1

Sumber: `grammars/README.md` llama.cpp.

```bash
# tata bahasa langsung
llama-cli -m MODEL --grammar-file skema.gbnf -p 'PROMPT'
llama-cli -m MODEL -j '{"type":"object","properties":{...}}'   # -j / --json: JSON Schema → GBNF otomatis
```

`llama-server` menerima `grammar` atau `json_schema` di body endpoint completion, dan `response_format`
di `/chat/completions` — jadi endpoint `:8080` yang sudah jalan bisa dipaksa patuh **tanpa ganti apa pun
di sisi klien**. Penting: *"The JSON schema is only used to constrain the model output and is not
injected into the prompt"* — modelnya tak diberi tahu skemanya, jadi **tetap jelaskan bentuk keluaran di
prompt**; grammar cuma mencegah penyimpangan.

Batasan GBNF yang wajib diketahui (semuanya terdokumentasi):
- `additionalProperties` **default `false`** demi performa.
- `prefixItems` rusak (pakai `items`); `$ref` bersarang rusak; `uniqueItems`/`contains`/`not`/kondisional tak didukung.
- Batasan numerik hanya untuk `"type": "integer"` — **bukan** `number`.
- `pattern` wajib diawali `^` dan diakhiri `$`; referensi skema jarak jauh tak didukung di versi C++.
- Jangan tulis `x? x? x?…` — sampling jadi sangat lambat; pakai `x{0,N}`.

### 2b. vLLM — anak tangga 1

Lima bentuk: `choice` · `regex` · `json` · `grammar` (EBNF) · `structural_tag`. Backend `xgrammar` /
`guidance`, plus mode `auto`. **Field `guided_json`/`guided_regex` dihapus di v0.12.0** — pakai parameter
`structured_outputs`. Jebakan khusus yang langsung kena kasus di sini: pada model ber-reasoning seperti
**Qwen3-Coder, structured output nonaktif kecuali dinyalakan** dengan
`--structured-outputs-config.enable_in_reasoning=True`.

### 2c. Claude / Anthropic — anak tangga 2

- **Strict tool use:** `strict: true` adalah **field top-level pada definisi tool** (sebelah
  `name`/`description`/`input_schema`) — **bukan** di `tool_choice`. Skema wajib punya
  `additionalProperties: false` + `required`. Hasilnya: `tool_use.input` dijamin lolos validasi.
- **Structured outputs:** `output_config: {format: {...}}` pada `messages.create()`. Parameter
  `output_format` yang lama sudah usang. Jalur termudah: `client.messages.parse()` — validasi otomatis.
- Tak kompatibel dengan programmatic tool calling, `disable_parallel_tool_use`, `tool_choice` yang
  dipaksa, dan tool MCP.

### 2d. API OpenAI-compatible (9router → Sonnet gratis, dsb.) — anak tangga 2

Sumber: dokumentasi Structured Outputs OpenAI.

- Wajib `"additionalProperties": false`, dan **semua properti harus `required`**.
- Field opsional dibuat lewat tipe nullable: `"type": ["string", "null"]` — bukan dengan menghapusnya
  dari `required`.
- Didukung: string/number/boolean/array/object, `enum`, `$ref` rekursif, objek & larik bersarang.
- **Terpotong** muncul sebagai `status: "incomplete"` + `incomplete_details.reason: "max_output_tokens"` —
  bukan sebagai error. Penolakan keamanan datang sebagai blok `type: "refusal"` terpisah, jadi bisa
  dideteksi program.

## 3. Kalau keluarannya bukan JSON (kasus paling sering: isi berkas)

Delegasi "tulis isi berkas X" tak bisa dijamin skema. Yang bisa ditegakkan:

1. **Satu artefak per panggilan.** Jangan pernah minta dua berkas sekaligus — model lemah akan
   menggabungkan, memberi judul, atau memotong yang kedua.
2. **Bingkai sentinel** yang tak mungkin muncul di isi, mis. `<<<MULAI>>>` … `<<<SELESAI>>>`. Ambil
   yang di antaranya secara mekanis. Sentinel penutup yang hilang = **terpotong**, bukan selesai —
   ini deteksi truncation yang tak butuh akses ke `finish_reason`.
3. **Kriteria terima yang dieksekusi**, ditulis sebelum mengirim: `node --check`, `python -m json.tool`,
   `tsc --noEmit`, `bash -n`, jumlah baris minimal, atau tes yang sudah ada. Kalau tak ada satu pun
   perintah yang bisa memvonis, tugas itu **bukan kandidat delegasi**.
4. **Prompt sistem yang menutup celah prosa:** "keluarkan HANYA isi berkas, tanpa pagar kode, tanpa
   penjelasan, tanpa kalimat pembuka." Tetap verifikasi — ini imbauan, bukan jaminan.

Vonis cepat sebelum hasil dipakai:

```bash
~/.claude/skills/weak-model-delegation/scripts/contract-check.sh <berkas> [--json|--sentinel] [--min-baris N]
```

## 4. Katalog tool: kecil itu bukan selera, itu akurasi

Bukti (Meta, arXiv 2605.24660, 23 Mei 2026 — registri BFCL 370 tool, MetaTool 199, ToolBench 3.251):
menampilkan **rata-rata ~7 tool** yang dipilih adaptif mencapai cakupan **90,3 % ± 2,4** di BFCL —
praktis menyamai menampilkan 50 tool (90,8 %) dengan kedalaman **7× lebih kecil**. Validasi hilirnya
menaikkan akurasi seleksi tool Claude dari **87,1 % → 93,1 %**. Pada kueri sulit ToolBench, pemilihan
adaptif menemukan jawaban di **16,7 %** kasus yang K=5 tetap **0 %**.

Sebabnya mekanis: perhatian model tersebar ke banyak nama yang mirip — ia lalu mengarang nama tool, atau
memanggil tool yang benar dengan **argumen milik tool lain**. Itu mode gagal #2, dipicu oleh #1.

**Jawaban resmi Anthropic** untuk katalog besar bukan "pilih sendiri", tapi tool search bawaan:
deklarasikan `tool_search_tool_regex_20251119` atau `tool_search_tool_bm25_20251119`, lalu tandai tool
lain `defer_loading: true`. Satu jebakan: **jangan defer semuanya** — tool pencarinya sendiri tak boleh
`defer_loading`, dan minimal satu tool harus non-deferred, kalau tidak API menolak `400 All tools have
defer_loading set`.

Aturan praktis: **≤ 10–20 tool aktif** per konteks; di atas itu pakai pemuatan tertunda, bukan harapan.

## 5. Paralel, berurutan, dan cara mengembalikan kegagalan

- **Paralel kalau mandiri, berurutan kalau bergantung** (output A jadi input B, atau keduanya mengubah
  keadaan yang sama).
- Satu pesan asisten boleh berisi banyak blok `tool_use`. Kembalikan **semua** `tool_result` dalam
  **satu pesan user**. Memecahnya ke beberapa pesan diam-diam melatih model berhenti memanggil paralel.
- Tool yang gagal **tetap dikembalikan**, dengan `is_error: true` — jangan dibuang. Isi pesannya string
  kegagalan yang terstruktur ("field `tanggal` harus ISO 8601, dapat '5 Juli'") supaya model bisa
  memperbaiki sendiri tanpa mengulang dari awal. Jangan lempar exception mentah.

## 6. Retry: ganti strategi, jangan kirim ulang

Kesalahan validasi adalah **sinyal**, bukan kecelakaan:

1. Percobaan 1 gagal validasi → kirim balik **pesan errornya** ke model (loop koreksi; pustaka seperti
   Instructor mengotomatiskan ini).
2. Percobaan 2 → **perkecil skema** atau pecah jadi dua panggilan. Skema besar = lebih banyak kesempatan
   salah.
3. Percobaan 3 → naik ke model yang lebih kuat, atau kerjakan sendiri.
4. Plafon 2–3 percobaan, tertulis. Mengulang prompt identik ke model yang sama bukan retry, itu doa.

Untuk kegagalan berbasis kuota (429/400/502) dan rantai fallback: `llm-quota-routing`.
Untuk job terjadwal yang melapor sukses padahal kosong: `honest-automation`.

## 7. Apa yang boleh didelegasikan

| Boleh | Jangan |
|---|---|
| Boilerplate dari spesifikasi lengkap; berkas dari cetakan | Keputusan arsitektur, wiring lintas berkas |
| Terjemahan/format ulang yang punya pemeriksa mekanis | Apa pun yang benar-salahnya cuma bisa dinilai dengan membacanya |
| Ekstraksi terstruktur dengan skema ketat | Debug penyebab akar |
| Volume besar keluaran seragam | Edit mikro (ongkos orkestrasi > hematnya) |

Aku tetap **reviewer akhir**: hasil delegasi lewat kriteria terima dulu, baru dipakai.

## 8. Jangan mewarisi yang basi

Catatan lama (termasuk catatan belajar Hermes) masih menganjurkan pola yang kini **ditolak API**:

- ❌ `anthropic-beta: interleaved-thinking-2025-05-14` + `thinking={"type":"enabled","budget_tokens":N}`.
  ✅ Sekarang `thinking: {type: "adaptive"}`; `budget_tokens` **dijawab 400** di Fable 5 / Opus 5 / 4.8 /
  4.7 / Sonnet 5, dan interleaved thinking menyala sendiri tanpa beta header di 4.6+.
- ❌ `output_format` → ✅ `output_config: {format: {...}}`.
- ❌ `guided_json` di vLLM → ✅ `structured_outputs` (dihapus v0.12.0).
- ❌ Prefill pesan asisten untuk memaksa format → **400** di Opus 5/4.8/4.7/4.6, Sonnet 5/4.6, Fable 5.
  Pakai structured outputs.

Aturan umum: sebelum menyalin resep API dari catatan mana pun yang berumur > 1 bulan, cek ke dokumen
resmi (untuk Claude: skill `claude-api`).

## Referensi

- `references/backend-recipes.md` — sintaks lengkap per backend (llama.cpp, vLLM, Anthropic,
  OpenAI-compatible) + tabel batasan yang terdokumentasi.
- `references/contract-patterns.md` — cetakan prompt delegasi, bingkai sentinel, kriteria terima
  per jenis artefak.
- `scripts/contract-check.sh` — vonis mekanis atas hasil delegasi (prosa pembungkus, terpotong,
  JSON tak valid, artefak ganda).
