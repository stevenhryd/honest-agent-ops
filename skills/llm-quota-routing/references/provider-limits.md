# Batas free-tier & jam reset (dicek 10 Jul 2026)

Semua jam reset dikonversi ke **WIB (UTC+7)** — zona mesin tempat pengukuran dilakukan. Sesuaikan.
Angka bisa berubah — selalu verifikasi ke dokumentasi resmi sebelum dipakai jadi keputusan keras.

## Jam reset (yang menentukan jadwal cron)

| Provider | Reset harian | = WIB | Catatan |
|---|---|---|---|
| OpenRouter (`:free`) | midnight UTC | **07:00** | dihitung per "current UTC day" |
| Gemini (free tier) | midnight Pacific | **14:00** (PDT) / 15:00 (PST) | RPD reset tengah malam PT |
| Groq (free) | rolling window | — | batas per menit/hari, bukan reset serentak |
| Antigravity via 9router | kuota individu, reset ~83 jam | — | pesan error menyebut sisa waktu persis |

**Konsekuensi:** jam 20:00–07:00 WIB adalah zona mati kalau armada hanya berisi OpenRouter + Gemini.
Jendela paling subur: **07:00–09:00** (OpenRouter segar) dan **14:00–17:00** (Gemini segar).

## Batas per model

### Gemini (free tier, per project — bukan per API key)
| Model | RPM | TPM | RPD |
|---|---|---|---|
| gemini-2.5-flash | 10 | 250.000 | 250 |
| gemini-2.5-flash-lite | 15 | 250.000 | 1.000 |

RPM 10 gampang kena oleh loop agentic yang menembak beruntun. Error: `429 RESOURCE_EXHAUSTED`,
`generate_content_free_tier_requests`.

### OpenRouter (`:free` variants)
- **20 request/menit** untuk semua model `:free`.
- **50 request/hari** kalau belum pernah beli kredit; **1.000/hari** kalau pernah beli ≥ $10.
- Model berbeda punya batas upstream berbeda → menyebar beban antar model itu sah.
- Rate-limit upstream muncul sebagai `429 "Provider returned error"` dengan `metadata.raw` berisi
  "temporarily rate-limited upstream".

> **50/hari itu kecil.** Satu run agentic bisa menghabiskan 15–30 panggilan. Artinya 2 run/hari, lalu kering.

### Groq (free)
- Batas per-model (llama-3.3-70b-versatile ≠ llama-3.1-8b-instant). Satu kering, yang lain bisa hidup.
- 8b-instant: RPD besar, tapi **TPM kecil** → prompt agentic besar bisa ditolak walau kuota harian penuh.
  Bagus sebagai bantalan panggilan kecil, buruk sebagai penyaji run penuh.
- **Menolak `reasoning_content` pada pesan assistant** → 400 permanen di percakapan multi-giliran yang
  pernah dilayani model thinking. Lihat SKILL.md.

## Model yang terbukti mati di setup ini (jangan dipasang lagi)

| Model | Gejala | Tanggal uji |
|---|---|---|
| `gemini/gemini-2.0-flash-lite` | 429 quota-0 sejak permintaan pertama | 3 Jul 2026 |
| `gemini/gemma-3-27b-it` | 404 lewat 9router | 3 Jul 2026 |
| `gemini/gemini-2.0-flash` | 429 | sebelum 3 Jul 2026 |
| `groq/llama-3.3-70b-versatile` | 400 `reasoning_content` unsupported (bukan kuota) | 10 Jul 2026 |
| `groq/llama-3.1-8b-instant` | idem | 10 Jul 2026 |

## Model yang hidup tapi TIDAK layak menulis

| Model | Masalah |
|---|---|
| `openrouter/nvidia/nemotron-3-super-120b-a12b:free` | tersedia luas, tapi output bahasa Indonesia tercemar kata Italia/Jerman/Vietnam, mengarang statistik, menimpa file utuh alih-alih edit sebagian |
| `openrouter/qwen/qwen3-coder:free` | model kode; prosa buruk + sering 429 upstream |

Keduanya boleh jadi tier untuk kerja **baca/analisis**, tidak untuk kerja **tulis-persisten**.

## Sumber

- https://ai.google.dev/gemini-api/docs/rate-limits
- https://openrouter.ai/docs/api-reference/limits
- https://console.groq.com/docs/errors
- Pengukuran langsung: `~/.9router/db/data.sqlite` (tabel `requestDetails`), 9–10 Jul 2026.
