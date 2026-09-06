# Sumber primer — dan apa yang TIDAK dijaminnya

Diverifikasi 1 Sep 2026. Tiap baris di sini dikutip dari sumbernya sendiri, bukan dari ringkasan blog.
Kolom terakhir yang paling berguna: **batas jaminannya**.

## systemd — `OnFailure=` / `OnSuccess=`

Sumber: `systemd.unit(5)`, halaman man lokal (systemd 260, Arch).

> `OnFailure=` — "A space-separated list of one or more units that are activated when this unit enters
> the **failed** state." (Added in version 201.)
>
> `OnSuccess=` — "…activated when this unit enters the **inactive** state." (Added in version 249.)

**Batas jaminan:** hanya transisi *state*. Unit yang selesai `exit 0` tanpa mengerjakan apa pun masuk
`inactive`, bukan `failed` — jadi `OnFailure=` **secara mekanis tak mungkin** menangkap run kosong, dan
`OnSuccess=` justru menyala. Tak ada setelan systemd apa pun yang mengubah ini; deteksi run kosong harus
datang dari perbandingan artefak, di luar systemd.

Catatan turunan: `SuccessExitStatus=` cuma memperluas daftar exit code yang dianggap sukses — memperlebar
lubang, bukan menutupnya.

## Prometheus — `absent()` / `absent_over_time()`

Sumber: dokumentasi resmi PromQL, *Query functions*.

> `absent(v instant-vector)` — mengembalikan vektor kosong bila vektor masukan berisi elemen; mengembalikan
> vektor 1-elemen bernilai `1` bila masukan tak punya elemen. "Useful for alerting on when no time series
> exist for a given metric name and label combination."
>
> `absent_over_time(v range-vector)` — varian rentang: `1` bila **tak ada sampel sama sekali** dalam rentang.
> "…for a certain amount of time."

Contoh dari dokumen: `absent_over_time(nonexistent{job="myjob"}[1h])` → `{job="myjob"}`.

**Batas jaminan:** mendeteksi *ketiadaan sinyal*, bukan *kualitas hasil*. Job yang tetap mengirim metrik
sambil menghasilkan nol tetap lolos. Metriknya karena itu harus **metrik keluaran** (jumlah artefak,
baris ditulis), bukan metrik kehidupan (uptime, heartbeat).

## healthchecks.io — model dead man's switch

Sumber: dokumentasi resmi.

- Layanan "listens for HTTP requests (pings) from your job", **diam selama ping datang tepat waktu**, dan
  **berbunyi saat ping tak datang**.
- Tiga sinyal: ping biasa = sukses · `/start` = mulai · `/fail` = gagal eksplisit. Ada juga bentuk
  `/<exitcode>`.
- **Grace Time** = tambahan waktu sebelum alarm. Bila `/start` dipakai, grace time sekaligus jadi
  **jarak maksimum yang diizinkan antara sinyal "start" dan "sukses"**.

**Batas jaminan:** membuktikan job *mulai dan selesai*, bukan job *menghasilkan*. Pasangan `/start` +
sukses menangkap job yang menguap di tengah — itu tepat kasus "rencana diumumkan, tulisan tak terjadi" —
tapi tetap butuh kontrak artefak untuk menangkap job yang selesai rapi tanpa hasil.

## Google SRE Workbook — *Alerting on SLOs*

Sumber: `sre.google/workbook/alerting-on-slos/`.

> "Having good SLOs that measure the reliability of your platform, **as experienced by your customers**,
> provides the highest-quality indication for when an on-call engineer should respond."

Isi bab: burn rate terhadap error budget; strategi berlapis yang direkomendasikan — 2 % anggaran dalam
1 jam (page), 5 % dalam 6 jam (page), 10 % dalam 3 hari (ticket).

**Batas jaminan — penting:** bab ini membahas layanan yang **melayani permintaan**. Kasus "sistem tampak
sehat tapi tak menghasilkan keluaran" **tidak dibahas**, termasuk untuk layanan lalu-lintas rendah yang
dibahas panjang lebar. Jangan mengutip SRE Workbook seolah ia menjawab masalah run kosong; prinsip
"alert pada outcome" diambil, mekanismenya harus dibuat sendiri.

## Yang sengaja TIDAK dijadikan sumber

Angka-angka populer soal observability agen (mis. "reranking +33–40 %", "cache hemat 40–80 %") beredar
lewat blog lapis dua. Beberapa memang berujung ke penelitian nyata — contoh terverifikasi: klaim
"hemat 85 % biaya sambil mempertahankan 95 % mutu GPT-4" berasal dari **RouteLLM** (arXiv 2406.18665,
ICLR 2025, rute GPT-4 Turbo ↔ Mixtral 8x7B pada MT Bench), bukan dari blog yang mengutipnya. Aturan yang
dipakai skill ini: **angka tanpa jalur ke sumber aslinya tidak dipakai sama sekali.**
