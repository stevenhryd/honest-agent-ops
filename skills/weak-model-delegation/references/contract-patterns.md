# Cetakan kontrak delegasi

Urutan yang benar: **tulis kriteria terima → tulis prompt → kirim → vonis**. Kalau langkah pertama
tak bisa diselesaikan, tugasnya bukan kandidat delegasi.

---

## Kerangka umum

```
KONTRAK DELEGASI
  artefak      : satu berkas / satu objek JSON  (JANGAN dua)
  bentuk       : <skema JSON | GBNF | bingkai sentinel>
  kriteria     : <perintah yang memvonis, exit 0 = terima>
  plafon       : 2 percobaan, strategi berbeda tiap kali
  penerima     : aku (reviewer akhir) — hasil tak dipakai sebelum lolos kriteria
```

---

## Pola 1 — Ekstraksi terstruktur (paling kuat)

Pakai kapan pun keluarannya bisa dinyatakan sebagai objek.

```jsonc
// skema — perhatikan tiga hal wajib untuk strict mode
{
  "type": "object",
  "additionalProperties": false,          // 1. tutup field liar
  "required": ["kode", "nama", "harga"],  // 2. SEMUA properti masuk required
  "properties": {
    "kode":  {"type": "string", "description": "Kode barang di ERP tujuan, mis. 'BRG-0012'"},
    "nama":  {"type": "string"},
    "harga": {"type": ["number", "null"]} // 3. opsional = nullable, bukan dihapus dari required
  }
}
```

Aturan penyusunan skema untuk model lemah:
- **Sekecil mungkin.** Skema besar = lebih banyak kesempatan salah. Pecah jadi dua panggilan kalau perlu.
- **Deskripsi tiap parameter menyebut format + contoh konkret**: `"Tanggal ISO 8601, mis. '2026-03-15'"`.
  Ini yang paling banyak menurunkan kesalahan argumen.
- **`enum` untuk himpunan tertutup**, jangan string bebas.
- **Nama fungsi/field mencerminkan niat**: `ambil_pesanan_v2` lebih baik dari `pesanan`. Versinya juga
  memungkinkan uji A/B pada perubahan deskripsi tanpa merusak pemanggil lama.

Kriteria terima: `python -m json.tool` + validasi skema (`jsonschema`, `pydantic`).

---

## Pola 2 — Isi berkas (tak bisa diskemakan)

```
Tulis isi lengkap berkas <lintasan>.

Keluarkan HANYA isi berkas, di antara dua penanda di bawah.
Tanpa pagar kode, tanpa penjelasan, tanpa kalimat pembuka atau penutup.

<<<MULAI>>>
(isi berkas di sini)
<<<SELESAI>>>
```

Kenapa sentinel, bukan pagar kode ``` : pagar kode muncul juga **di dalam** isi (README, dokumentasi),
jadi tak bisa dipakai sebagai batas. Sentinel dipilih yang mustahil ada di isi.

Vonis mekanis:
- `<<<MULAI>>>` tak ada → model membungkus dengan prosa → tolak.
- `<<<SELESAI>>>` tak ada → **terpotong**, bukan selesai → tolak, dan ini deteksi truncation yang tak
  butuh akses `finish_reason`.
- Ada teks di luar pasangan sentinel → buang, jangan dipakai sebagai isi.
- Dua pasang sentinel → model mengerjakan dua artefak → tolak, ulangi satu per satu.

Kriteria terima menyusul sesuai jenis berkas: `node --check`, `bash -n`, `tsc --noEmit`,
`python -m py_compile`, `psql -f … --dry-run`, atau tes yang sudah ada.

---

## Pola 3 — Transformasi baris demi baris

Untuk terjemahan, format ulang, penomoran ulang. Kontrak terkuatnya bukan skema, melainkan **invarian
yang bisa dihitung**:

```
- jumlah baris keluaran HARUS sama dengan masukan
- kolom pertama tiap baris tidak boleh berubah
- tak boleh ada baris kosong tambahan
```

Vonis: `wc -l` dua sisi + `cut -f1 | diff`. Invarian yang bisa dihitung mengalahkan pemeriksaan mata
untuk keluaran besar — dan justru keluaran besar itulah alasan mendelegasikan.

---

## Pola 4 — Banyak berkas

Jangan. Satu panggilan = satu artefak. Untuk N berkas, N panggilan, dengan kontrak yang sama diulang.
Model lemah yang diminta banyak berkas akan: menggabungkan isinya, memberi judul pemisah karangan
sendiri, atau memotong berkas terakhir tanpa memberi tahu.

Kalau N besar dan tiap berkas berpola sama, kirim **cetakan + tabel nilai**, dan minta satu berkas per
panggilan dari baris tabel yang sama — bukan minta model mengarang variasinya sendiri.

---

## Kalimat prompt sistem yang terbukti perlu

```
Keluarkan HANYA <artefak>. Tanpa penjelasan, tanpa pagar kode, tanpa kalimat pembuka.
Kalau ada yang tak bisa kamu tentukan, tulis TIDAK_TAHU pada nilai itu — jangan mengarang.
Jangan meringkas, jangan memotong. Kalau isi terlalu panjang, tetap tulis lengkap.
```

Baris kedua penting: tanpa jalan keluar eksplisit, model lemah **mengisi tebakan** ketimbang mengaku
tak tahu — dan tebakan yang berformat benar lolos semua pemeriksaan sintaks.

---

## Yang menentukan tugas ini layak didelegasikan atau tidak

Satu pertanyaan: **perintah apa yang akan memvonis hasilnya?**

- Ada jawabannya → delegasikan.
- Jawabannya "aku baca dulu" → kerjakan sendiri. Membaca hasil delegasi memakai token yang sama
  mahalnya dengan mengerjakan, ditambah risiko salah yang tak kelihatan.
