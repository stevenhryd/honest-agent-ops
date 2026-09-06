#!/usr/bin/env bash
# audit-job.sh — memvonis job tak-berpenunggu dari BUKTI, bukan dari statusnya sendiri.
#
# KONTRAK KELUARAN (jangan diubah — ini yang bikin alat ini aman dipakai di cron):
#   stdout berisi  = ADA TEMUAN (run kosong / tak ada bukti)
#   stdout kosong  = tak ada temuan (job terbukti bekerja)
#   exit 0         = alat berhasil menilai — TERMASUK saat ada temuan
#   exit 2         = ALAT INI SENDIRI RUSAK (argumen salah, lintasan tak ada, date tak valid)
# Menumpuk "ada temuan" ke exit code melahirkan lingkaran umpan balik: penjadwal menandai job
# `error`, audit besok membaca kegagalan itu sebagai temuan tambahan, merah selamanya.
#
# Pakai:
#   audit-job.sh NAMA --bukti 'GLOB|DIR' [--bukti ...] --sejak 'SPEC' [--minimal N] [--verbose]
#
#   --bukti    berkas/glob/direktori yang ISINYA seharusnya bertambah. Boleh diulang.
#              Glob WAJIB dikutip supaya tak diekspansi shell lebih dulu.
#   --sejak    apa pun yang dimengerti `date -d`: '6 hours ago', 'today 15:00', ISO 8601.
#              Isi dengan waktu MULAI run yang sedang dinilai.
#   --minimal  berapa artefak baru minimal supaya disebut bekerja (default 1).
#   --verbose  cetak vonis walau tak ada temuan (untuk dijalankan manual).
#
# Contoh:
#   audit-job.sh mentor-reflection --bukti '~/.hermes/knowledge/*.md' --sejak '2026-08-31 15:00'
set -uo pipefail

nama=""; sejak=""; minimal=1; verbose=0; bukti=()

rusak() { printf 'ALAT RUSAK (%s): %s\n' "${nama:-audit-job}" "$1" >&2; exit 2; }

[ $# -ge 1 ] || rusak "tak ada argumen. Pakai: audit-job.sh NAMA --bukti GLOB --sejak SPEC"
nama="$1"; shift
case "$nama" in -*) rusak "argumen pertama harus NAMA job, bukan opsi '$nama'";; esac

while [ $# -gt 0 ]; do
  case "$1" in
    --bukti)   [ $# -ge 2 ] || rusak "--bukti butuh nilai"; bukti+=("$2"); shift 2 ;;
    --sejak)   [ $# -ge 2 ] || rusak "--sejak butuh nilai"; sejak="$2";    shift 2 ;;
    --minimal) [ $# -ge 2 ] || rusak "--minimal butuh nilai"; minimal="$2"; shift 2 ;;
    --verbose) verbose=1; shift ;;
    *) rusak "opsi tak dikenal: $1" ;;
  esac
done

[ "${#bukti[@]}" -gt 0 ] || rusak "wajib ada minimal satu --bukti (job tanpa kontrak keluaran tak bisa dinilai)"
[ -n "$sejak" ]          || rusak "wajib ada --sejak (waktu mulai run yang dinilai)"
case "$minimal" in ''|*[!0-9]*) rusak "--minimal harus bilangan bulat, dapat '$minimal'";; esac

ambang=$(date -d "$sejak" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || rusak "--sejak tak dimengerti date: '$sejak'"

baru=0; total=0; terbaru=""; tak_ada=()

for pola in "${bukti[@]}"; do
  # ~ tidak diekspansi di dalam string berkutip — lakukan manual.
  case "$pola" in "~"/*) pola="$HOME${pola#\~}";; esac

  if [ -d "$pola" ]; then
    akar="$pola"; saring=(-type f)
  elif [ -e "$pola" ]; then
    akar=$(dirname -- "$pola"); saring=(-type f -path "$pola")
  else
    case "$pola" in
      *[*?[]*) # ada wildcard: akar = awalan direktori terpanjang yang benar-benar ada
        akar="${pola%%/\**}"; [ "$akar" = "$pola" ] && akar=$(dirname -- "$pola")
        while [ -n "$akar" ] && [ ! -d "$akar" ]; do
          induk=$(dirname -- "$akar"); [ "$induk" = "$akar" ] && break; akar="$induk"
        done
        saring=(-type f -path "$pola") ;;
      *) # lintasan biasa yang memang tak ada — jangan naik ke induknya
        tak_ada+=("$pola"); continue ;;
    esac
  fi

  if [ ! -d "$akar" ]; then tak_ada+=("$pola"); continue; fi

  # find bisa exit != 0 cuma karena "Permission denied" pada cabang lain; itu bukan alat rusak.
  daftar=$(find "$akar" "${saring[@]}" -printf '%T@ %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null)
  if [ -n "$daftar" ]; then t=$(printf '%s\n' "$daftar" | wc -l); else t=0; fi
  n=$(find "$akar" "${saring[@]}" -newermt "$ambang" -printf 'x\n' 2>/dev/null | wc -l)
  baru=$((baru + n)); total=$((total + t))

  m=$(printf '%s\n' "$daftar" | sort -rn | head -1)
  if [ -n "$m" ]; then
    if [ -z "$terbaru" ] || [ "${m%% *}" \> "${terbaru%% *}" ]; then terbaru="$m"; fi
  fi
done

[ "${#tak_ada[@]}" -eq "${#bukti[@]}" ] && rusak "tak satu pun lintasan bukti ada: ${tak_ada[*]}"

jejak="${terbaru#* }"
[ -n "$jejak" ] || jejak="(tak ada berkas sama sekali di lintasan bukti)"

if [ "$baru" -ge "$minimal" ]; then
  [ "$verbose" -eq 1 ] && printf '%s: BEKERJA — %s artefak baru sejak %s (terbaru: %s)\n' \
    "$nama" "$baru" "$ambang" "$jejak"
  exit 0
fi

if [ "$total" -eq 0 ]; then
  printf '%s: TAK ADA BUKTI — lintasan bukti kosong sama sekali. Job ini belum pernah menghasilkan apa pun.\n' "$nama"
else
  printf '%s: RUN KOSONG — 0 artefak baru sejak %s (butuh %s). Artefak terbaru: %s\n' \
    "$nama" "$ambang" "$minimal" "$jejak"
fi
[ "${#tak_ada[@]}" -gt 0 ] && printf '%s: catatan — lintasan bukti tak ada: %s\n' "$nama" "${tak_ada[*]}"
exit 0
