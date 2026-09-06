# Playbook diagnosis — perintah siap pakai

Contoh konkretnya memakai stack 9router + hermes-agent. Polanya berlaku untuk gateway LLM mana pun
yang menyimpan log permintaan — ganti path DB dan nama tabelnya.
**Selalu backup DB router sebelum mengubah combo.**

## 0. Backup dulu

```bash
cp ~/.9router/db/data.sqlite ~/.9router/db/data.sqlite.bak-$(date +%Y%m%d-%H%M)
```

## 1. Tally per-model per-status (sebab utama muncul di sini)

```bash
sqlite3 -header -column ~/.9router/db/data.sqlite "
SELECT substr(timestamp,1,10) d, model, status, COUNT(*) n
FROM requestDetails WHERE timestamp >= date('now','-2 days')
GROUP BY d,model,status ORDER BY d, n DESC;"
```

Baca hasilnya begini:
- model **100% error** → tersangka kegagalan permanen (schema/404/kunci), bukan kuota.
- model **campur sukses+error** → rate limit; obatnya jadwal & backoff.
- model **100% sukses tapi output jelek** → masalah mutu, bukan infrastruktur.

## 2. Error mentah upstream (jangan percaya kode HTTP terluar)

```bash
python3 - <<'EOF'
import sqlite3, json
import os
db=sqlite3.connect(os.path.expanduser(os.environ.get('NINEROUTER_DB','~/.9router/db/data.sqlite')))
for (m,) in db.execute("SELECT DISTINCT model FROM requestDetails WHERE status='error'"):
    r=db.execute("SELECT data FROM requestDetails WHERE model=? AND status='error' "
                 "ORDER BY timestamp DESC LIMIT 1",(m,)).fetchone()
    d=json.loads(r[0]); pr=d.get('providerResponse') or d.get('response') or {}
    err=pr.get('error') if isinstance(pr,dict) else pr
    print(f"### {m}\n{str(err)[:240]}\n")
EOF
```

Field pentingnya `providerResponse.error` — di situ kode aslinya (400 vs 429) terbaca.

## 3. Peta jam sukses → jadwal cron

```bash
cd ~/.hermes/cron/output/<job-id>
for f in *.md; do head -1 "$f" | grep -q FAILED || echo "${f:11:2}:00"; done | sort | uniq -c
```

Jam dengan sukses terbanyak = jendela reset kuota. Jadwalkan run di situ, bukan merata sepanjang hari.

## 4. Ekonomi run (apakah cadence terlalu rapat?)

```bash
cd ~/.hermes/cron/output/<job-id>
tot=$(ls *.md | wc -l); fail=$(grep -l FAILED *.md 2>/dev/null | wc -l)
echo "total=$tot gagal=$fail  → panggilan terbuang ≈ $((fail * TIER * RETRY))"
```

Kalau > 80% gagal: kuota harian habis di jam-jam awal, sisanya cuma bising. Turunkan cadence ke
`sukses/hari + 1-2 percobaan`, semuanya di dalam jendela reset.

## 5. Uji mutu artefak (langkah yang paling sering dilewat)

```bash
# bahasa asing nyelip di catatan berbahasa Indonesia
grep -rEn "spiegazione|Werkspace|khách|decyzion|„|“" ~/.hermes/knowledge/*.md
# paragraf dobel
python3 - <<'EOF'
import glob,collections,os
for f in glob.glob(os.path.expanduser('~/.hermes/knowledge/*.md')):
    paras=[p.strip() for p in open(f).read().split('\n\n') if len(p.strip())>200]
    for p,c in collections.Counter(paras).items():
        if c>1: print(f, "PARAGRAF DOBEL:", p[:70])
EOF
# slug kembar (kandidat merge)
ls ~/.hermes/knowledge/*.md | sed 's#.*/##;s/\.md$//' | sort | awk '{
  n=$0; gsub(/-(in|of|for|the|a)-/,"-",n); if (n==prev) print "MIRIP:", prev, "<->", $0; prev=n }'
```

## 6. Ubah combo 9router (lewat API, bukan edit SQLite langsung)

```bash
node -e '
// path modul global ikut prefix npm: `npm root -g` untuk menemukannya.
const api=require(process.env.NINEROUTER_CLIENT
  || require("child_process").execSync("npm root -g").toString().trim()
     + "/9router/src/cli/api/client.js");
(async()=>{
  const r=await api.getCombos();
  const c=r.data.combos.find(x=>x.name==="hermes-learn");
  await api.updateCombo(c.id,{name:c.name,models:["gemini/gemini-2.5-flash","gemini/gemini-2.5-flash-lite","ag/claude-sonnet-4-6"]});
  const v=await api.getCombos();
  console.log(v.data.combos.find(x=>x.name==="hermes-learn").models);
})();'
```

`getCombos()` mengembalikan `{success, data:{combos:[{id,name,models[]}]}}`.

## 7. Ubah jadwal cron hermes (JANGAN tulis jobs.json manual)

```bash
hermes cron edit <job-id> --schedule "0 14,16,18,20 * * *"
hermes cron list   # verifikasi di sumber otoritatif: store gateway, bukan file
```

`~/.hermes/cron/jobs.json` hanya cermin tampilan. Menulis `schedule` sebagai string biasa merusak
`hermes cron list` (`'str' object has no attribute 'get'`) — field itu harus objek hasil
`cron.jobs.parse_schedule(expr)`. Trigger `hermes cron run` di luar jendela jadwal akan dilewati diam-diam.

## 8. Jangan pernah cetak kredensial

Muat ke variabel, pakai langsung, jangan echo:

```bash
KEY=$(grep -m1 -E '^(OPENAI_API_KEY|NINEROUTER_API_KEY)=' ~/.hermes/.env | cut -d= -f2-)
curl -sS -H "Authorization: Bearer $KEY" http://127.0.0.1:20128/v1/models >/dev/null && echo "router ok"
```
