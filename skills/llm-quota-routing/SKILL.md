---
name: llm-quota-routing
description: "Diagnose and design quota-aware LLM fallback routing across multiple providers. Use when an agent/cron/router keeps failing with 429, 400, 502, when free-tier quota runs out, when a fallback chain 'walks all tiers and dies', when scheduling agent work around daily quota resets, or when a weak fallback model silently degrades output quality. Triggers: 429, rate limit, RPD, RPM, TPM, quota exhausted, fallback chain, model failover, circuit breaker, retry berplafon, 9router, combo, free tier, dead tier, reasoning_content 400, cross-provider schema."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), disuling bersama Claude (Opus) dari post-mortem armada model 3–10 Jul 2026
license: MIT
---

# LLM Quota Routing — bikin armada model gratis benar-benar jalan

Fallback chain yang panjang **bukan** ketahanan. Chain panjang yang tiap tier-nya diam-diam mati adalah
mesin pembakar kuota: tiap panggilan bayar N tier × M retry sebelum sampai model yang hidup, dan model yang
hidup itu biasanya yang paling jelek.

Skill ini dipakai untuk: **mendiagnosis** kenapa armada model gagal, **merancang ulang** rantainya, dan
**menjadwalkan** kerja agen ke jam kuota hidup.

## Hukum inti (urut kepentingan)

1. **"429" bukan diagnosis.** Kegagalan yang dilaporkan agen selalu berasal dari **tier terakhir**. Error yang
   kamu lihat adalah error model paling bawah, bukan sebab utama. Selalu bongkar per-tier, per-status.
   Proxy/router membungkus 429/502 upstream jadi HTTP 400 — jangan percaya kode HTTP terluar.

2. **Bedakan empat kegagalan yang mirip di mata pengguna:**

   | Gejala | Sebab | Obat |
   |---|---|---|
   | 429 `RESOURCE_EXHAUSTED` | kuota harian/menit habis | jadwalkan ke jendela reset, kurangi cadence |
   | 400 `invalid_request_error` | **inkompatibilitas schema**, permanen | buang tier itu, atau bersihkan payload |
   | 502 / timeout | endpoint upstream ngambek | retry berjitter, circuit-break |
   | sukses tapi output sampah | model fallback terlalu lemah | **gerbang kualitas**: lebih baik gagal terang |

3. **Kuota itu ember per-model, bukan per-akun.** Satu model kering tidak berarti seluruh provider kering.
   Uji ping kecil per model sebelum mencoret tier. Sebaliknya, TPM yang kecil bisa menolak satu permintaan
   agentic besar walau RPD masih banyak — model itu bisa jadi bantalan untuk panggilan kecil saja.

4. **Reset kuota punya zona waktu, dan itu menentukan jadwal kerjamu.** Jangan jadwalkan agen di jam yang
   dijamin kering. Lihat `references/provider-limits.md`.

5. **Retry harus berplafon.** Exponential backoff + jitter, hormati `Retry-After` / `x-ratelimit-*`. Retry
   langsung tanpa jeda mengubah satu 429 jadi badai yang mempertahankan kelebihan beban itu sendiri. Setelah
   plafon habis: **lapor jelas**, jangan loop selamanya.

6. **Tier mati harus dicabut, bukan dibiarkan.** Tiap tier mati menambah latensi dan retry ke tiap langkah
   agen. Circuit breaker: N kegagalan berturut-turut pada satu tier → buka sirkuit 60s, tutup bertahap.
   Untuk kegagalan **permanen** (400 schema, 404 model), cabut dari chain — bukan circuit-break.

7. **Gerbang kualitas > ketersediaan.** Untuk pekerjaan yang **menulis ke penyimpanan persisten** (basis
   ilmu, memori, dokumen, DB), model fallback yang lemah lebih berbahaya daripada kegagalan. Output yang
   rusak halus (bahasa campur aduk, angka mengarang, file ditimpa) baru ketahuan berhari-hari kemudian.
   **Aturan:** chain untuk pekerjaan tulis-persisten hanya berisi model yang kamu percaya. Kalau habis,
   **gagal terang-terangan**. Chain panjang boleh untuk pekerjaan baca/analisis yang hasilnya dibuang.

8. **Router menyembunyikan identitas provider — dan itu bikin bug.** Klien agen sering menyesuaikan payload
   berdasarkan `base_url`/nama provider (quirk per-vendor). Lewat proxy, semua terlihat seperti satu host,
   jadi deteksi quirk gagal. Kasus nyata: lihat "Kontaminasi schema" di bawah.

## Kontaminasi schema lintas provider (jebakan paling mahal)

Model yang berpikir (Gemini 2.5, DeepSeek, Kimi, nemotron) mengembalikan `reasoning_content` pada pesan
assistant. Klien menyimpannya ke riwayat percakapan. Pada giliran berikutnya, riwayat itu **diputar ulang**
ke model mana pun yang kebetulan melayani. Provider yang tidak mengenal field itu menolak:

```
400 invalid_request_error: 'messages.7' : for 'role:assistant' the following must be satisfied
[('messages.7' : property 'reasoning_content' is unsupported)]
```

Akibatnya: tier itu **400 permanen mulai giliran ke-3 setiap run**, terlihat seperti "provider mati", padahal
sehat. Beberapa provider justru **mewajibkan** echo-back field ini (DeepSeek V4 thinking, Kimi/Moonshot,
Xiaomi MiMo) — jadi tidak bisa dibuang begitu saja secara global.

**Cara benar (urut preferensi):**
1. Bersihkan payload **di router**, per-provider tujuan: strip `reasoning_content`/`reasoning` untuk provider
   yang menolaknya, pertahankan untuk yang mewajibkan. Router tahu tujuan sebenarnya; klien tidak.
2. Kalau tidak bisa menyentuh router: jangan campur model thinking dan non-thinking dalam satu chain
   untuk percakapan multi-giliran.
3. Paling murah: cabut tier yang menolak dari chain.

Cek dulu apakah klienmu punya deteksi quirk berbasis host (`base_url_host_matches`) — kalau ya, routing lewat
proxy melumpuhkannya.

## Playbook diagnosis (30 menit, tanpa menebak)

Jalankan `scripts/router-health.sh` kalau targetnya 9router. Kalau bukan, tiru urutannya:

1. **Tally per-model per-status** dari log router, bukan dari log agen. Cari model yang 100% error → tersangka
   permanen. Cari model yang error/sukses campur → rate limit.
2. **Baca error mentah upstream**, bukan yang sudah dibungkus. Di 9router: kolom `data` →
   `providerResponse.error`. Kode di dalamnya (400 vs 429) yang menentukan obat.
3. **Peta jam sukses.** Kelompokkan run sukses per jam. Puncak sukses = jendela reset kuota. Itu jadwal kerjamu.
4. **Hitung ekonomi run.** `run gagal/hari × tier × retry` = panggilan terbuang. Kalau 90% run gagal, cadence
   terlalu rapat: kuota harian habis dalam 2 jam pertama, sisanya bikin bising.
5. **Periksa mutu output, bukan cuma status.** Buka 2-3 artefak yang ditulis oleh run "sukses". Bahasa asing
   nyelip, paragraf dobel, file ditimpa total = model penyaji terlalu lemah, walaupun statusnya hijau.

## Aturan merancang chain

- **Panjang chain ≤ 3** untuk kerja tulis-persisten. Urut: kualitas terbaik → cadangan sekelas → cadangan
  terakhir yang masih layak. Bukan "semua yang gratis".
- Setiap tier harus lolos tiga uji: **hidup** (ping), **kompatibel** (schema), **layak** (mutu output).
- Cadence kerja = kapasitas nyata, bukan harapan. Ukur: `sukses/hari` selama seminggu, jadwalkan sebanyak itu
  + 1-2 percobaan cadangan, semuanya di dalam jendela reset.
- Satu percobaan per jendela lebih baik daripada empat percobaan yang saling memakan RPM.
- Catat per-run: model penyaji, status, token. Tanpa itu, "agennya bodoh" dan "providernya mati" tidak
  terbedakan.

## Referensi

- `references/provider-limits.md` — batas free-tier + jam reset (WIB) untuk Gemini, Groq, OpenRouter, dll.
- `references/diagnosis-playbook.md` — perintah SQL/shell siap pakai untuk 9router + hermes-agent.
- `scripts/router-health.sh` — tally per-model per-status, error mentah terakhir, peta jam sukses.

## Sumber

- Google — [Gemini API rate limits](https://ai.google.dev/gemini-api/docs/rate-limits) (diakses 2026-07-10)
- OpenRouter — [API rate limits](https://openrouter.ai/docs/api-reference/limits) (diakses 2026-07-10)
- Groq — [API error codes](https://console.groq.com/docs/errors) · [Reasoning](https://console.groq.com/docs/reasoning) (diakses 2026-07-10)
- NousResearch/hermes-agent — [issue #11089: Groq `reasoning_content` unsupported](https://github.com/NousResearch/hermes-agent/issues/11089) (diakses 2026-07-10)
- vercel/ai — [issue #8056: Groq models receiving unsupported `reasoning` field](https://github.com/vercel/ai/issues/8056) (diakses 2026-07-10)
- Maxim AI — [Retries, fallbacks, and circuit breakers in LLM apps](https://www.getmaxim.ai/articles/retries-fallbacks-and-circuit-breakers-in-llm-apps-a-production-guide/) (diakses 2026-07-10)
- TrueFoundry — [Rate limiting AI agents: 3-layer gateway](https://www.truefoundry.com/blog/rate-limiting-ai-agents-preventing-llm-api-exhaustion) (diakses 2026-07-10)
- Bukti lapangan: post-mortem armada model agen Hermes di satu mini-PC self-host, 3–10 Jul 2026
  (218 run gagal, 24 sukses).
