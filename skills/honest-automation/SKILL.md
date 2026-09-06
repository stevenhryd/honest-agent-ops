---
name: honest-automation
description: "Design and audit unattended work — cron, systemd timers, PM2 processes, scheduled agents, watchdogs, refresh/sync scripts — so that a green status cannot mean zero work done. Use when a job reports ok/healthy but nothing changed, when adding any scheduled or background task, when a dashboard/monitor is healthy while output stopped, or when deciding what a job must prove before it may claim success. Triggers: cron, crontab, systemd timer, OnFailure, PM2, watchdog, heartbeat, dead man's switch, scheduled agent, background job, silent failure, no-op run, 'last_status=ok tapi tak ada hasil', hijau tapi nol, job lapor ok, audit pencatatan, stale artifact, absent metric, monitoring blind spot."
version: 1.0.0
author: Steven Hariyadi (stevenhryd), disuling bersama Claude (Opus) dari insiden nyata 26 Agu–1 Sep 2026 + sumber primer
license: MIT
---

# Honest Automation — bikin "ok" ada artinya

Kerja yang tak ditunggui manusia punya satu penyakit khas: **statusnya ditulis oleh pelakunya sendiri.**
Job memutuskan sendiri ia berhasil, lalu menulis `ok`. Tak ada yang mengadu klaim itu dengan dunia.
Akibatnya bukan alarm palsu — akibatnya **diam yang salah**: berbulan-bulan hijau, nol hasil.

> **Hukum induk:** status ditulis pelaku, bukti ditulis dunia. Kalau keduanya berasal dari sumber yang
> sama, statusnya tak bernilai apa pun.

Skill ini untuk dua hal: **memvonis** job yang sudah jalan, dan **merancang** job baru yang tak bisa bohong.

## Kapan dipakai

Pasang skill ini begitu ada kata: cron, systemd timer, PM2, watchdog, scheduled agent, sinkronisasi
berkala, refresh, backup, "jalan tiap malam" — atau begitu muncul kalimat **"katanya jalan tapi kok
nggak ada hasilnya"**.

Bedanya dengan `verification-before-completion`: skill itu soal **aku** tak boleh mengaku selesai tanpa
bukti di dalam sesi. Skill ini soal **mesin** yang jalan saat tak ada siapa-siapa.

## 1. Kelas kegagalan: hijau tapi nol

Lima bentuk, semuanya pernah benar-benar terjadi di sistem yang melahirkan skill ini:

| Bentuk | Contoh nyata | Yang bohong |
|---|---|---|
| **Langkah mustahil dilaporkan beres** | Job `hermes-peta` disuruh `graphify --update` 77× — `execute_code` diblokir cron by design; `graphify-out/` kosong sejak 2 Jul, `last_status=ok` tiap kali | Job tak tahu perintahnya mustahil |
| **Rencana diumumkan, tulisan tak terjadi** | 31 Agu 16:00/18:00/20:00 `mentor-reflection`: "Saya akan menggabungkan…" lalu berhenti; tak ada berkas berubah sesudah 14:02; tiga-tiganya `ok` | Kalimat niat dibaca sebagai hasil |
| **Indikator sehat di lapis yang salah** | fxbot: PM2 hijau, log bergerak tiap 20 menit, watchdog SEHAT — sementara probe macet 70 menit; telemetri mati 5 minggu tanpa ketahuan | Indikator mengukur lapis lain |
| **Perintah vonis salah alat** | `pgrep -c terminal64.exe` selalu 0 di Wine → dua kali memvonis "MT5 mati" dan menuliskannya sebagai fakta | Alat ukurnya sendiri tak pernah diadu |
| **Auditor menandai dirinya sendiri gagal** | Pembungkus audit meneruskan `exit 1` ("ada temuan") → Hermes menandai job `error` → audit membaca "cron gagal" sebagai bolong tambahan → merah selamanya | Dua sinyal beda ditumpuk di satu kanal |

Ciri bersama: **tak satu pun terdeteksi oleh pemantauan proses.** Semua prosesnya benar-benar jalan.

## 2. Kenapa alat standar tak menangkapnya

Ini bukan kelalaian konfigurasi — memang di luar jangkauan alatnya:

- **`OnFailure=` systemd** hanya menyala saat unit masuk state **`failed`** (`systemd.unit(5)`, sejak v201).
  Job yang `exit 0` sambil tak mengerjakan apa pun tak pernah masuk `failed` → `OnFailure=` **tak mungkin**
  menangkapnya. `OnSuccess=` malah menyala (unit jadi `inactive`).
- **Exit code** cuma melaporkan apakah proses selesai, bukan apakah kerjanya terjadi. `exit 0` = "aku tak
  crash", bukan "aku menghasilkan sesuatu".
- **cron** membuang stdout ke surel yang tak dibaca (atau ke `/dev/null`); tak ada konsep "hasil".
- **PM2 `online`** = prosesnya ada. Sama sekali tak bicara soal kemajuan.
- **Google SRE Workbook** benar menyuruh alert pada *outcome* yang dialami pengguna, bukan pada sebab —
  tapi bab *Alerting on SLOs* seluruhnya soal error budget & burn rate; **kasus "sehat tapi tak ada keluaran"
  tak dibahas**. Jangan cari jawabannya di sana; harus dirancang sendiri.

Yang menangkapnya cuma satu jenis sinyal: **ketiadaan keluaran yang seharusnya ada.**
Prometheus menyebutnya `absent_over_time()` — "berguna untuk alert ketika tak ada time series untuk
kombinasi nama metrik & label tertentu **selama jangka waktu tertentu**". Model dead-man switch
(healthchecks.io) sama: sistem **diam selama ping datang tepat waktu**, dan **berbunyi justru saat ping
tak datang**. Pakai `/start` + sukses supaya jarak antara "mulai" dan "selesai" ikut terukur — job yang
mulai lalu menguap terdeteksi, bukan cuma job yang tak pernah mulai.

## 3. Empat hukum

### L1 — Preflight kemampuan: jangan menjadwalkan langkah yang mustahil

Sebelum satu langkah masuk job tak-berpenunggu, jawab: **apakah langkah ini bisa berhasil di lingkungan
itu, tanpa manusia?** Kalau tidak, buang langkahnya — jangan berharap ia gagal dengan berisik.

Daftar mustahil yang sudah terbukti di lapangan:

| Langkah | Kenapa mustahil unattended |
|---|---|
| `execute_code` di cron Hermes | Diblokir by design — tak ada manusia yang bisa menyetujui |
| `pkexec …` dari sesi SSH | Butuh agen polkit grafis; tak ada di sesi SSH → pakai `sudo -S` |
| `sudo` langsung dari Claude Code | Tak ada tty |
| Apa pun yang butuh kuota LLM | Kuota habis = job mati total, bukan job pelan |

**Uji cepat:** jalankan langkah itu satu kali di lingkungan yang persis sama (user, sesi, izin, tanpa tty).
Kalau tak bisa dibuktikan sekali pun secara manual, ia tak layak dijadwalkan.

Konsekuensi desain: **kerja yang butuh shell jangan ditaruh di job ber-LLM.** Mode skrip (`--no-agent`)
nol token, tak bisa kena kuota, tak tersandung blokir tool.

### L2 — Kontrak keluaran yang bisa dipalsukan

Tiap job wajib menyebutkan, **tertulis di berkasnya sendiri**, satu kalimat:

```
BERHASIL := <artefak> bertambah/berubah sejak <kapan>, terbaca lewat <perintah>
```

Tanpa kalimat itu, "berhasil" cuma perasaan. Aturannya:

- **Artefak, bukan aktivitas.** Baris log baru bukan artefak — log bergerak sambil kerja berhenti itu
  justru bentuk kegagalan #3. Artefak = berkas yang isinya dipakai orang lain, baris baru di basis data,
  commit, berkas hasil.
- **Kebasian diukur dari ISI, bukan umur.** "Graph lebih tua dari 7 hari" melahirkan alarm palsu (5 buah,
  26 Agu). Yang benar: "ada berkas sumber **lebih baru** dari graph-nya". Bandingkan dua hal nyata,
  jangan bandingkan satu hal dengan kalender.
- **Bisa dipalsukan (falsifiable).** Kontrak yang tak mungkin gagal tak mengukur apa-apa. Kalau kamu tak
  bisa menyebut satu keadaan dunia yang membuat kontrak ini berbunyi, kontraknya kosong.
- **Kosong itu sah, tapi harus disengaja.** Job yang memang tak selalu menghasilkan (mis. "lapor kalau ada
  temuan") kontraknya: *stdout kosong = senyap = tak ada temuan*. Bedakan dari *tak jalan*: itu urusan
  heartbeat (L3), bukan urusan artefak.

### L3 — Satu kanal, satu arti

Tiga sinyal berbeda; jangan pernah ditumpuk:

| Sinyal | Kanal | Arti |
|---|---|---|
| Ada temuan / ada hasil | **stdout** | isi = laporkan · kosong = senyap |
| Alatnya sendiri rusak | **exit ≠ 0** | tak bisa dijalankan sama sekali |
| Job tak pernah jalan | **ketiadaan ping/artefak** | dideteksi dari luar, oleh pihak lain |

Pelanggarannya melahirkan lingkaran umpan balik: pembungkus audit meneruskan `exit 1` sebagai "ada
temuan" → penjadwal menandai `error` → audit besok membaca "job gagal" sebagai bolong tambahan → merah
selamanya. Pembungkus job pelapor **selalu `exit 0`**; temuan lewat stdout.

Dan yang paling penting: **auditor bukan pelaku.** Job yang sama tak boleh mengerjakan dan sekaligus
menilai dirinya. Vonis harus datang dari proses lain yang cuma membaca dunia.

### L4 — Plafon, dan tiap percobaan strategi berbeda

Buntu bukan alasan berhenti diam, juga bukan alasan mengulang selamanya:

- Tiap percobaan pakai **strategi berbeda** (ganti model, sederhanakan cakupan, pecah tugas) — bukan
  kirim ulang yang sama. Mengulang permintaan identik ke server yang kelebihan beban memperparah.
- **Plafon ditulis eksplisit** di kode/konfigurasi (jumlah percobaan · batas waktu · batas token), bukan
  tersirat, supaya bisa diaudit dan disetel.
- Aksi **non-idempoten** (kirim, transfer, posting) jangan di-retry otomatis tanpa kunci idempotensi.
- Habis semua strategi → **laporan yang menyebut apa yang sudah dicoba dan kenapa mentok**, jangan diam.

## 4. Cara memvonis job yang sudah jalan

Urutannya penting — jangan mulai dari log.

1. **Tanya kontraknya.** Artefak apa yang seharusnya bertambah? Kalau tak ada yang bisa menyebut, itu
   temuan pertama: job tanpa kontrak.
2. **Adu jam jalan dengan jam artefak.**
   ```bash
   ~/.claude/skills/honest-automation/scripts/audit-job.sh <nama> \
       --bukti '<glob>' --sejak '<ISO atau "6 jam">' [--minimal 1]
   ```
   Jalan sesudah artefak terakhir = **run kosong**. Itu vonisnya, bukan dugaan.
3. **Baca jawaban akhir run, bukan statusnya.** Untuk job ber-LLM: kalimat terakhir yang berbentuk
   *niat* ("saya akan…", "mulai dengan membaca…") sesudah itu berhenti = run kosong walau `ok`.
   Kode yang dicetak sebagai teks (`print(...)`) = tanda tool eksekusi diblokir lalu di-fallback jadi
   prosa — langgar L1.
4. **Uji alat ukurnya sendiri sekali.** Sebelum memvonis lewat shell, buktikan perintahnya mengembalikan
   yang kamu kira (`pgrep` vs `pgrep -f` di Wine). Alat ukur yang belum pernah diadu adalah tebakan
   berpakaian angka.
5. **Hitung yield, bukan jumlah run.** `270 run` tak berarti apa-apa; `81 artefak dari 270 run` berarti.

## 5. Cara memasang job yang tak bisa bohong

Cetakan minimal — berlaku untuk cron, systemd timer, maupun scheduled agent:

```bash
#!/usr/bin/env bash
# KONTRAK: berhasil := ada berkas baru di ~/keluaran/ sejak run sebelumnya.
# stdout berisi = ada temuan · exit != 0 = alat rusak (BUKAN "ada temuan").
set -uo pipefail

kerja() { : "lakukan kerjanya di sini"; }

sebelum=$(find ~/keluaran -type f -newermt '-1 day' | wc -l)
kerja || { printf 'ALAT RUSAK: kerja() gagal dijalankan\n'; exit 2; }
sesudah=$(find ~/keluaran -type f -newermt '-1 day' | wc -l)

if [ "$sesudah" -le "$sebelum" ]; then
  printf 'RUN KOSONG: kerja() selesai tanpa menambah berkas di ~/keluaran\n'
fi
exit 0
```

Tiga hal yang membuatnya jujur: kontrak tertulis di baris pertama · perbedaan artefak diukur sebelum
dan sesudah · run kosong **melapor lewat stdout** sambil tetap `exit 0`.

Untuk lapisan luar (job tak pernah jalan sama sekali), pasang salah satu:

- **Prometheus**: `absent_over_time(<metrik_job>[<periode + kelonggaran>])` → alert.
- **Dead-man switch** (healthchecks.io atau apa pun): ping `/start` di awal, ping sukses di akhir;
  grace time mengatur jarak maksimum antara keduanya.
- **Tanpa jaringan**: satu job auditor terpisah yang membaca mtime artefak semua job lain, jalan lebih
  jarang dari job terpantau. Pola rujukan: langkah `--no-agent` (nol token) + skrip audit terjadwal
  terpisah yang mengadu artefak, bukan status.

## 6. Jebakan

- **Auditor yang menghitung dirinya sendiri.** Kalau auditor masuk daftar yang diaudit, satu kegagalannya
  jadi dua temuan besok. Kecualikan dirinya secara eksplisit.
- **Daftar pengecualian tanpa alasan.** Berkas "sengaja kosong" (`.audit-abai` dan sejenisnya) wajib memuat
  **alasan per baris**. Tanpa alasan itu bukan keputusan, itu bolong yang disembunyikan.
- **Ambang umur absolut.** "> N hari = basi" selalu melahirkan alarm palsu di berkas yang memang jarang
  berubah. Bandingkan isi dengan isi.
- **Menyamakan "identik" dengan "mutakhir".** `korpus == graph` cuma membuktikan dua salinan cocok; dua-duanya
  bisa sama-sama basi. Perlu cek ketiga: **sumber lebih baru dari korpus**.
- **Menambah jadwal untuk menutupi run kosong.** 4×/hari yang 3 di antaranya nol lebih buruk dari 1×/hari
  yang selesai: bakar kuota, dan menyamarkan yield di balik jumlah run.
- **Alarm yang tak seorang pun baca.** Kanal keluar (stdout ke penjadwal, notifikasi, berkas laporan) harus
  yang benar-benar dilihat manusia; kalau tidak, jujur pun percuma.

## Referensi

- `references/failure-catalog.md` — katalog lengkap bentuk kegagalan + tanda pengenalnya di log/output.
- `references/primary-sources.md` — kutipan sumber primer (systemd, Prometheus, healthchecks, SRE Workbook)
  dan apa persisnya yang **tidak** dijamin masing-masing.
- `scripts/audit-job.sh` — vonis "bekerja / run kosong / tak pernah jalan" dari bukti artefak.
