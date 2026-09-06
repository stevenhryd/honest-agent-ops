# Diagnosis playbook — ready-to-run commands

The concrete examples use a 9router + hermes-agent stack. The pattern applies to any LLM gateway that
stores request logs — substitute your database path and table names.
**Always back up the router database before changing a combo.**

## 0. Back up first

```bash
cp ~/.9router/db/data.sqlite ~/.9router/db/data.sqlite.bak-$(date +%Y%m%d-%H%M)
```

## 1. Tally per model per status (the root cause shows up here)

```bash
sqlite3 -header -column ~/.9router/db/data.sqlite "
SELECT substr(timestamp,1,10) d, model, status, COUNT(*) n
FROM requestDetails WHERE timestamp >= date('now','-2 days')
GROUP BY d,model,status ORDER BY d, n DESC;"
```

Read the result like this:
- a model at **100% errors** → suspect a permanent failure (schema/404/key), not quota.
- a model with **mixed successes and errors** → rate limiting; the cure is scheduling and backoff.
- a model at **100% success but with poor output** → a quality problem, not an infrastructure one.

## 2. Raw upstream error (never trust the outermost HTTP code)

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

The field that matters is `providerResponse.error` — that is where the real code (400 vs 429) is readable.

## 3. Map of successful hours → cron schedule

```bash
cd ~/.hermes/cron/output/<job-id>
for f in *.md; do head -1 "$f" | grep -q FAILED || echo "${f:11:2}:00"; done | sort | uniq -c
```

The hour with the most successes is the quota reset window. Schedule runs there, not spread evenly
across the day.

## 4. Run economics (is the cadence too tight?)

```bash
cd ~/.hermes/cron/output/<job-id>
tot=$(ls *.md | wc -l); fail=$(grep -l FAILED *.md 2>/dev/null | wc -l)
echo "total=$tot failed=$fail  → wasted calls ≈ $((fail * TIERS * RETRIES))"
```

If more than 80% fail: the daily quota is spent in the first hours and the rest is just noise. Lower the
cadence to `successes/day + 1–2 attempts`, all inside the reset window.

## 5. Artifact quality test (the step most often skipped)

```bash
# stray foreign words in notes that should be in one language
grep -rEn "spiegazione|Werkspace|khách|decyzion|„|“" ~/.hermes/knowledge/*.md
# duplicated paragraphs
python3 - <<'EOF'
import glob,collections,os
for f in glob.glob(os.path.expanduser('~/.hermes/knowledge/*.md')):
    paras=[p.strip() for p in open(f).read().split('\n\n') if len(p.strip())>200]
    for p,c in collections.Counter(paras).items():
        if c>1: print(f, "DUPLICATE PARAGRAPH:", p[:70])
EOF
# near-duplicate slugs (merge candidates)
ls ~/.hermes/knowledge/*.md | sed 's#.*/##;s/\.md$//' | sort | awk '{
  n=$0; gsub(/-(in|of|for|the|a)-/,"-",n); if (n==prev) print "SIMILAR:", prev, "<->", $0; prev=n }'
```

## 6. Change a 9router combo (through the API, not by editing SQLite directly)

```bash
node -e '
// the global module path follows the npm prefix: use `npm root -g` to find it.
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

`getCombos()` returns `{success, data:{combos:[{id,name,models[]}]}}`.

## 7. Change the hermes cron schedule (do NOT write jobs.json by hand)

```bash
hermes cron edit <job-id> --schedule "0 14,16,18,20 * * *"
hermes cron list   # verify against the authoritative source: the gateway store, not the file
```

`~/.hermes/cron/jobs.json` is only a display mirror. Writing `schedule` as a plain string breaks
`hermes cron list` (`'str' object has no attribute 'get'`) — that field must be an object produced by
`cron.jobs.parse_schedule(expr)`. Triggering `hermes cron run` outside the scheduled window is skipped
silently.

## 8. Never print credentials

Load into a variable, use it directly, never echo it:

```bash
KEY=$(grep -m1 -E '^(OPENAI_API_KEY|NINEROUTER_API_KEY)=' ~/.hermes/.env | cut -d= -f2-)
curl -sS -H "Authorization: Bearer $KEY" http://127.0.0.1:20128/v1/models >/dev/null && echo "router ok"
```
