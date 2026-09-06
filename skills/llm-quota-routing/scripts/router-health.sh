#!/usr/bin/env bash
# router-health.sh — potret kesehatan armada model 9router.
# Pakai: ./router-health.sh [hari-ke-belakang]   (default 2)
# Tidak mengubah apa pun. Tidak mencetak kredensial.
#
# KONTRAK KELUARAN (sama dengan scripts/audit-job.sh di skill honest-automation):
#   stdout = laporan   ·   exit 0 = alat berhasil menilai   ·   exit 2 = ALAT INI SENDIRI RUSAK
# Model mati BUKAN kegagalan alat — itu temuan, dan temuan dilaporkan lewat stdout. Menumpuknya
# ke exit code membuat penjadwal menandai job `error`, lalu audit berikutnya membaca kegagalan itu
# sebagai bolong tambahan: merah selamanya.
set -uo pipefail

rusak() { printf 'ALAT RUSAK (router-health): %s\n' "$1" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || rusak "sqlite3 tak terpasang"
command -v python3 >/dev/null 2>&1 || rusak "python3 tak terpasang"

DAYS="${1:-2}"
DB="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"

[ -r "$DB" ] || rusak "DB router tidak terbaca: $DB (setel NINEROUTER_DB kalau letaknya lain)"

echo "== Tally per-model per-status ($DAYS hari terakhir) =="
sqlite3 -header -column "$DB" "
SELECT substr(timestamp,1,10) AS tgl, model, status, COUNT(*) AS n
FROM requestDetails
WHERE timestamp >= date('now','-${DAYS} days')
GROUP BY tgl, model, status
ORDER BY tgl, n DESC;"

echo
echo "== Vonis per model =="
# Vonis butuh KODE error asli, bukan sekadar rasio: ok=0 bisa berarti kuota kering (429)
# atau cacat permanen (400/404). Dua-duanya "mati", obatnya beda jauh.
python3 - "$DB" "$DAYS" <<'EOF'
import sqlite3, json, sys, re
db, days = sqlite3.connect(sys.argv[1]), int(sys.argv[2])
rows = db.execute(
    "SELECT model, SUM(status='success'), SUM(status='error') FROM requestDetails "
    "WHERE timestamp >= date('now', ?) GROUP BY model", (f'-{days} days',)).fetchall()

def last_code(model):
    """Kode HTTP asli dari upstream. JSON-nya bersarang & ter-escape, jadi cari di teks mentah."""
    r = db.execute("SELECT data FROM requestDetails WHERE model=? AND status='error' "
                   "ORDER BY timestamp DESC LIMIT 1", (model,)).fetchone()
    if not r:
        return None
    try:
        d = json.loads(r[0])
        # providerResponse sering {} kosong -> error aslinya ada di response
        pr = d.get('providerResponse') or d.get('response') or {}
    except Exception:
        pr = {}
    if isinstance(pr, dict) and isinstance(pr.get('status'), int):
        return pr['status']
    m = re.search(r'\\?"code\\?":\s*(\d{3})|\[(\d{3})\]', str(pr) or r[0])
    return int(m.group(1) or m.group(2)) if m else None

for model, ok, err in rows:
    if ok + err == 0:
        continue
    code = last_code(model) if err else None
    if ok == 0 and code == 429:
        v = "KERING      -> kuota habis; jadwalkan ke jendela reset, turunkan cadence"
    elif ok == 0 and code in (400, 404):
        v = f"CACAT ({code}) -> permanen (schema/model tak dikenal); CABUT dari chain"
    elif ok == 0:
        v = "MATI TOTAL  -> baca error mentah di bawah sebelum memutuskan"
    elif err == 0:
        v = "SEHAT       -> cek MUTU output; status hijau tidak menjamin tulisan bagus"
    elif err * 100 // (ok + err) > 60:
        v = "TERSENDAT   -> rate limit; perbaiki jadwal + backoff berjitter"
    else:
        v = "WAJAR"
    print(f"  {model:<46} ok={ok:<4} err={err:<4} {v}")
EOF

echo
echo "== Error mentah upstream terakhir per model =="
python3 - "$DB" <<'EOF'
import sqlite3, json, sys
db = sqlite3.connect(sys.argv[1])
rows = db.execute("SELECT DISTINCT model FROM requestDetails WHERE status='error'").fetchall()
for (m,) in rows:
    r = db.execute("SELECT data FROM requestDetails WHERE model=? AND status='error' "
                   "ORDER BY timestamp DESC LIMIT 1", (m,)).fetchone()
    if not r:
        continue
    try:
        d = json.loads(r[0])
        pr = d.get('providerResponse') or d.get('response') or {}
        err = pr.get('error') if isinstance(pr, dict) else pr
    except Exception:
        err = r[0]
    err = str(err).replace('\n', ' ')[:200]
    print(f"  {m}\n    {err}\n")
EOF

echo "== Ingat =="
echo "  - Error yang dilaporkan agen = error TIER TERAKHIR, bukan sebab utama."
echo "  - 400 invalid_request = permanen (cabut tier). 429 = kuota (jadwal ulang). 502 = retry berjitter."
echo "  - Model hidup tapi lemah tetap berbahaya untuk kerja tulis-persisten."
