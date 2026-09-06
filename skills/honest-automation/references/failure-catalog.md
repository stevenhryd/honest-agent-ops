# Katalog kegagalan "hijau tapi nol" — tanda pengenal & vonisnya

Dipakai saat memeriksa job yang sudah jalan. Cari **tanda pengenal**, bukan pesan error — kelas ini
memang tak menghasilkan error.

---

## F1 · Langkah mustahil dilaporkan beres

**Tanda pengenal**
- Prompt/skrip menyuruh sesuatu yang lingkungannya larang (tool diblokir, butuh tty, butuh persetujuan).
- Berkas tujuan tak pernah ada / tak pernah berubah sejak job dibuat.
- Status selalu `ok`, tak pernah sekali pun `error` — kestabilan sempurna itu sendiri mencurigakan.

**Contoh** `hermes-peta` disuruh `graphify --update` 77 run; `execute_code` diblokir cron by design;
`graphify-out/` kosong sejak 2 Jul.

**Vonis** Jalankan langkah itu manual di lingkungan yang persis sama. Kalau tak bisa sekali pun → langkahnya
dibuang dari job, bukan diulang lebih sering.

---

## F2 · Rencana diumumkan, tulisan tak terjadi

**Tanda pengenal (khas job ber-LLM)**
- Jawaban akhir berbentuk **niat**, bukan hasil: "Saya akan menggabungkan…", "Mulai dengan membaca X dan Y.",
  "Setelah itu saya akan update Z."
- Jawaban terpotong di tengah kalimat ("Saya menemukan").
- Kode dicetak sebagai teks (`print(isi_baru)`) alih-alih dieksekusi → tool eksekusi diblokir lalu
  di-fallback jadi prosa. Ini F1 yang menyamar jadi F2.
- Berkas sasaran tak berubah, padahal run melaporkan akan mengubahnya.

**Contoh** 31 Agu 2026, tiga run berturut (16:00 · 18:00 · 20:00) `mentor-reflection` — semua `ok`, tak ada
satu pun berkas di `~/.hermes/knowledge/`, `.archive/`, atau vault berubah sesudah 14:02.

**Vonis** `mtime` artefak terbaru < waktu mulai run. Tak perlu membaca isinya.

---

## F3 · Indikator sehat di lapis yang salah

**Tanda pengenal**
- Yang dipantau: proses hidup, log bergerak, watchdog hijau. Yang ditanyakan: apakah kerjanya maju.
- Watchdog memakai jalur berbeda dari kerja sesungguhnya, jadi tak ikut putus saat kerjanya putus.
- Log bergerak tiap N menit dengan isi yang selalu sama.

**Contoh** fxbot — pola ini muncul **8 kali**: telemetri mati 5 minggu tanpa ketahuan; probe macet 70 menit
sementara PM2 hijau, log bergerak tiap 20 menit, watchdog SEHAT.

**Vonis** Adu indikator dengan **keluaran yang seharusnya bertambah** (baris telemetri baru, posisi baru,
tiket baru). Keluaran tak bertambah + indikator hijau = **indikatornya yang salah**, bukan sistemnya sehat.

---

## F4 · Alat ukur yang belum pernah diadu

**Tanda pengenal**
- Vonis dijatuhkan lewat satu perintah shell yang tak pernah diuji pada kasus positif.
- Perintah mengembalikan 0/kosong, lalu ketiadaan itu dibaca sebagai fakta.

**Contoh** `pgrep -c terminal64.exe` selalu 0 untuk proses di bawah Wine (butuh `pgrep -f`) → dua kali
memvonis "MT5 mati" dan menuliskannya di commit sebagai fakta.

**Vonis** Jalankan alat ukurnya saat kondisi yang dicari **benar-benar ada**. Kalau ia tak menyala di situ,
angkanya tak bernilai. Alat ukur yang belum diadu = tebakan berpakaian angka.

---

## F5 · Auditor menandai dirinya sendiri gagal (lingkaran umpan balik)

**Tanda pengenal**
- Pembungkus meneruskan `exit≠0` yang artinya "ada temuan".
- Penjadwal menandai job `error`; auditor besok membaca "job gagal" sebagai temuan tambahan.
- Jumlah temuan naik monoton tanpa ada yang benar-benar memburuk.

**Contoh** 28 Agu 2026 — `~/.hermes/scripts/audit-pencatatan.sh` meneruskan `exit 1` apa adanya → merah
selamanya sampai dipisahkan.

**Vonis & obat** Pembungkus **selalu `exit 0`**; temuan lewat stdout; `exit>1` khusus "alatnya rusak".
Auditor dikecualikan dari daftar yang diaudit, eksplisit.

---

## F6 · Basi diukur dari kalender

**Tanda pengenal**
- Aturan berbentuk "lebih tua dari N hari = basi".
- Alarm menyala pada berkas yang memang jarang berubah dan memang benar.

**Contoh** 26 Agu 2026 — ambang umur absolut pada graph melahirkan **5 alarm palsu**.

**Vonis** Ganti jadi perbandingan isi-lawan-isi: "ada **sumber** lebih baru dari **turunannya**".

---

## F7 · Dua salinan cocok, dua-duanya basi

**Tanda pengenal**
- Cek berbentuk `A == B` antar dua turunan (korpus vs graph, cache vs indeks).
- Tak ada satu pun cek yang menyentuh **sumber** aslinya.

**Contoh** 28 Agu 2026 — 18 berkas sumber lebih baru dari `sources/`, sementara cek `korpus-vs-graph`
melaporkan identik dan audit diam.

**Vonis** Tambah cek ketiga: **sumber → korpus**. Rantai turunan wajib dicek dari ujung paling hulu.

---

## F8 · Jadwal dinaikkan untuk menutupi run kosong

**Tanda pengenal**
- Frekuensi naik tanpa ada perbaikan sebab.
- Yield (artefak ÷ run) turun sementara jumlah run naik.

**Contoh** `mentor-reflection` 4×/hari menghasilkan ±1 catatan/hari — 3 run bakar kuota tiap hari,
dan jumlah run yang besar menyamarkan yield-nya.

**Vonis** Hitung **yield**, bukan jumlah run. Turunkan frekuensi sampai tiap run punya kontrak yang
benar-benar terpenuhi.
