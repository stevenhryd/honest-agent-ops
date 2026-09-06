#!/usr/bin/env bash
# contract-check.sh — memvonis hasil delegasi SEBELUM dipakai.
#
# KONTRAK KELUARAN (sengaja BEDA dari scripts/audit-job.sh di skill honest-automation):
#   exit 0 = DITERIMA        exit 1 = DITOLAK (ada temuan)      exit 2 = ALAT INI RUSAK
# Alat ini adalah GERBANG yang dipanggil sinkron (`contract-check.sh f && pakai f`), jadi vonisnya
# memang harus ada di exit code. Pelapor terjadwal punya aturan sebaliknya (stdout = temuan,
# selalu exit 0) supaya penjadwal tak menandai job `error` — jangan tukar keduanya.
#
# Pakai:
#   contract-check.sh BERKAS [--json] [--sentinel] [--min-baris N]
#                            [--mulai TANDA] [--selesai TANDA] [--diam]
set -uo pipefail

berkas=""; mode_json=0; mode_sentinel=0; min_baris=0; diam=0
mulai='<<<MULAI>>>'; selesai='<<<SELESAI>>>'
temuan=0

rusak() { printf 'ALAT RUSAK: %s\n' "$1" >&2; exit 2; }
lapor() { [ "$diam" -eq 1 ] || printf '  ✗ %s\n' "$1"; temuan=$((temuan+1)); }

[ $# -ge 1 ] || rusak "pakai: contract-check.sh BERKAS [--json] [--sentinel] [--min-baris N]"
berkas="$1"; shift
[ -f "$berkas" ] || rusak "berkas tak ada: $berkas"

while [ $# -gt 0 ]; do
  case "$1" in
    --json)      mode_json=1; shift ;;
    --sentinel)  mode_sentinel=1; shift ;;
    --min-baris) [ $# -ge 2 ] || rusak "--min-baris butuh nilai"; min_baris="$2"; shift 2 ;;
    --mulai)     [ $# -ge 2 ] || rusak "--mulai butuh nilai";     mulai="$2";     shift 2 ;;
    --selesai)   [ $# -ge 2 ] || rusak "--selesai butuh nilai";   selesai="$2";   shift 2 ;;
    --diam)      diam=1; shift ;;
    *) rusak "opsi tak dikenal: $1" ;;
  esac
done
case "$min_baris" in ''|*[!0-9]*) rusak "--min-baris harus bilangan bulat";; esac

[ "$diam" -eq 1 ] || printf 'contract-check: %s\n' "$berkas"

# --- 0. kosong -------------------------------------------------------------
if [ ! -s "$berkas" ]; then lapor "berkas kosong (0 bita)"; printf 'DITOLAK (1 temuan)\n'; exit 1; fi

baris=$(wc -l < "$berkas")
awal=$(head -c 400 "$berkas")
akhir=$(tail -c 200 "$berkas")

# --- 1. prosa pembungkus ---------------------------------------------------
pola_prosa='^[[:space:]]*(tentu[!,. ]|baik[!,. ]|berikut |oke[!,. ]|sure[!,. ]|certainly[!,. ]|here.{0,2}s |here is |i.{0,2}ll |i will |saya akan |di bawah ini )'
if printf '%s' "$awal" | grep -qiE "$pola_prosa"; then
  lapor "diawali kalimat prosa — model membungkus artefak dengan penjelasan"
fi
if printf '%s' "$akhir" | grep -qiE '(semoga membantu|hope this helps|let me know|beri tahu saya|silakan sesuaikan)'; then
  lapor "diakhiri kalimat prosa — ada teks di luar artefak"
fi

# --- 2. pagar kode di ujung ------------------------------------------------
if printf '%s' "$awal" | head -1 | grep -qE '^[[:space:]]*```'; then
  lapor "diawali pagar kode \`\`\` — buang pagar sebelum dipakai (atau pakai bingkai sentinel)"
fi

# --- 3. tanda terpotong ----------------------------------------------------
if [ -n "$(tail -c 1 "$berkas")" ]; then
  lapor "tak diakhiri baris baru — kemungkinan terpotong di tengah"
fi
if printf '%s' "$akhir" | grep -qE '(\.\.\.|…|\[truncated\]|dan seterusnya)[[:space:]]*$'; then
  lapor "diakhiri elipsis/'dan seterusnya' — isi diringkas, bukan lengkap"
fi

# --- 4. tebakan yang berformat benar ---------------------------------------
if grep -qE '(TODO|TIDAK_TAHU|FIXME|<isi di sini>|placeholder|lorem ipsum)' "$berkas"; then
  lapor "berisi placeholder/TIDAK_TAHU — artefak belum lengkap (ini jujur, tapi belum bisa dipakai)"
fi

# --- 5. mode sentinel ------------------------------------------------------
if [ "$mode_sentinel" -eq 1 ]; then
  n_mulai=$(grep -cF -- "$mulai" "$berkas" || true)
  n_selesai=$(grep -cF -- "$selesai" "$berkas" || true)
  [ "$n_mulai"   -eq 0 ] && lapor "penanda mulai '$mulai' tak ada — keluaran tak mengikuti bingkai"
  [ "$n_selesai" -eq 0 ] && lapor "penanda selesai '$selesai' tak ada — TERPOTONG, bukan selesai"
  { [ "$n_mulai" -gt 1 ] || [ "$n_selesai" -gt 1 ]; } && \
    lapor "ada $n_mulai/$n_selesai pasang penanda — lebih dari satu artefak dalam satu panggilan"
fi

# --- 6. mode json ----------------------------------------------------------
if [ "$mode_json" -eq 1 ]; then
  isi="$berkas"
  if [ "$mode_sentinel" -eq 1 ]; then
    isi=$(mktemp) || rusak "mktemp gagal"
    sed -n "/$(printf '%s' "$mulai" | sed 's/[]\/$*.^[]/\\&/g')/,/$(printf '%s' "$selesai" | sed 's/[]\/$*.^[]/\\&/g')/p" \
      "$berkas" | sed '1d;$d' > "$isi"
  fi
  if command -v python3 >/dev/null 2>&1; then
    galat=$(python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$isi" 2>&1) \
      || lapor "JSON tak valid: $(printf '%s' "$galat" | tail -1)"
  else
    lapor "python3 tak ada — JSON tak bisa divalidasi (jangan anggap lolos)"
  fi
  [ "$isi" != "$berkas" ] && rm -f "$isi"
fi

# --- 7. panjang minimal ----------------------------------------------------
if [ "$min_baris" -gt 0 ] && [ "$baris" -lt "$min_baris" ]; then
  lapor "cuma $baris baris, minimal $min_baris — kemungkinan diringkas"
fi

if [ "$temuan" -eq 0 ]; then
  [ "$diam" -eq 1 ] || printf 'DITERIMA (%s baris)\n' "$baris"
  exit 0
fi
[ "$diam" -eq 1 ] || printf 'DITOLAK (%s temuan)\n' "$temuan"
exit 1
