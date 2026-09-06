#!/usr/bin/env bash
# router-health.sh — health snapshot of a 9router model fleet.
# Usage: ./router-health.sh [days-back]   (default 2)
# Changes nothing. Prints no credentials.
#
# OUTPUT CONTRACT (identical to scripts/audit-job.sh in the honest-automation skill):
#   stdout = the report   ·   exit 0 = the tool judged successfully   ·   exit 2 = THE TOOL ITSELF IS BROKEN
# A dead model is NOT a tool failure — it is a finding, and findings are reported on stdout. Stacking them
# onto the exit code makes the scheduler mark the job `error`, and the next audit then reads that failure
# as an additional gap: red forever.
set -uo pipefail

broken() { printf 'TOOL BROKEN (router-health): %s\n' "$1" >&2; exit 2; }
command -v sqlite3 >/dev/null 2>&1 || broken "sqlite3 is not installed"
command -v python3 >/dev/null 2>&1 || broken "python3 is not installed"

DAYS="${1:-2}"
DB="${NINEROUTER_DB:-$HOME/.9router/db/data.sqlite}"

[ -r "$DB" ] || broken "router database not readable: $DB (set NINEROUTER_DB if it lives elsewhere)"

echo "== Tally per model per status (last $DAYS days) =="
sqlite3 -header -column "$DB" "
SELECT substr(timestamp,1,10) AS day, model, status, COUNT(*) AS n
FROM requestDetails
WHERE timestamp >= date('now','-${DAYS} days')
GROUP BY day, model, status
ORDER BY day, n DESC;"

echo
echo "== Verdict per model =="
# The verdict needs the REAL error code, not just a ratio: ok=0 can mean a dry quota (429) or a
# permanent defect (400/404). Both read as "dead", but the cures are entirely different.
python3 - "$DB" "$DAYS" <<'EOF'
import sqlite3, json, sys, re
db, days = sqlite3.connect(sys.argv[1]), int(sys.argv[2])
rows = db.execute(
    "SELECT model, SUM(status='success'), SUM(status='error') FROM requestDetails "
    "WHERE timestamp >= date('now', ?) GROUP BY model", (f'-{days} days',)).fetchall()

def last_code(model):
    """The real upstream HTTP code. The JSON is nested and escaped, so search the raw text too."""
    r = db.execute("SELECT data FROM requestDetails WHERE model=? AND status='error' "
                   "ORDER BY timestamp DESC LIMIT 1", (model,)).fetchone()
    if not r:
        return None
    try:
        d = json.loads(r[0])
        # providerResponse is often an empty {} -> the real error sits in response
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
        v = "DRY          -> quota exhausted; schedule into the reset window, lower the cadence"
    elif ok == 0 and code in (400, 404):
        v = f"DEFECT ({code}) -> permanent (schema/unknown model); REMOVE from the chain"
    elif ok == 0:
        v = "FULLY DEAD   -> read the raw error below before deciding"
    elif err == 0:
        v = "HEALTHY      -> check output QUALITY; a green status does not guarantee good writing"
    elif err * 100 // (ok + err) > 60:
        v = "STRUGGLING   -> rate limited; fix the schedule and add jittered backoff"
    else:
        v = "NORMAL"
    print(f"  {model:<46} ok={ok:<4} err={err:<4} {v}")
EOF

echo
echo "== Last raw upstream error per model =="
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

echo "== Remember =="
echo "  - The error an agent reports is the LAST TIER's error, not the root cause."
echo "  - 400 invalid_request = permanent (remove the tier). 429 = quota (reschedule). 502 = jittered retry."
echo "  - A model that is alive but weak is still dangerous for persistent-write work."
