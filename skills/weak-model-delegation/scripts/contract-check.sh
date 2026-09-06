#!/usr/bin/env bash
# contract-check.sh — pass verdict on a delegated result BEFORE it is used.
#
# OUTPUT CONTRACT (deliberately DIFFERENT from scripts/audit-job.sh in the honest-automation skill):
#   exit 0 = ACCEPTED        exit 1 = REJECTED (findings exist)      exit 2 = THIS TOOL IS BROKEN
# This tool is a GATE called synchronously (`contract-check.sh f && use f`), so its verdict belongs in
# the exit code. Scheduled reporters follow the opposite rule (stdout = findings, always exit 0) so the
# scheduler does not mark the job `error` — never swap the two.
#
# Usage:
#   contract-check.sh FILE [--json] [--sentinel] [--min-lines N]
#                          [--begin MARKER] [--end MARKER] [--quiet]
set -uo pipefail

file=""; mode_json=0; mode_sentinel=0; min_lines=0; quiet=0
begin='<<<BEGIN>>>'; end='<<<END>>>'
findings=0

broken() { printf 'TOOL BROKEN: %s\n' "$1" >&2; exit 2; }
report() { [ "$quiet" -eq 1 ] || printf '  ✗ %s\n' "$1"; findings=$((findings+1)); }

[ $# -ge 1 ] || broken "usage: contract-check.sh FILE [--json] [--sentinel] [--min-lines N]"
file="$1"; shift
[ -f "$file" ] || broken "file does not exist: $file"

while [ $# -gt 0 ]; do
  case "$1" in
    --json)      mode_json=1; shift ;;
    --sentinel)  mode_sentinel=1; shift ;;
    --min-lines) [ $# -ge 2 ] || broken "--min-lines needs a value"; min_lines="$2"; shift 2 ;;
    --begin)     [ $# -ge 2 ] || broken "--begin needs a value";     begin="$2";     shift 2 ;;
    --end)       [ $# -ge 2 ] || broken "--end needs a value";       end="$2";       shift 2 ;;
    --quiet)     quiet=1; shift ;;
    *) broken "unknown option: $1" ;;
  esac
done
case "$min_lines" in ''|*[!0-9]*) broken "--min-lines must be an integer";; esac

[ "$quiet" -eq 1 ] || printf 'contract-check: %s\n' "$file"

# --- 0. empty --------------------------------------------------------------
if [ ! -s "$file" ]; then
  report "file is empty (0 bytes)"
  [ "$quiet" -eq 1 ] || printf 'REJECTED (1 finding)\n'
  exit 1
fi

lines=$(wc -l < "$file")
head_txt=$(head -c 400 "$file")
tail_txt=$(tail -c 200 "$file")

# --- 1. wrapper prose ------------------------------------------------------
# Both English and Indonesian openers: a delegated model may answer in either.
prose_re='^[[:space:]]*(sure[!,. ]|certainly[!,. ]|of course[!,. ]|okay[!,. ]|ok[!,. ]|here.{0,2}s |here is |below is |i.{0,2}ll |i will |tentu[!,. ]|baik[!,. ]|berikut |oke[!,. ]|saya akan |di bawah ini )'
if printf '%s' "$head_txt" | grep -qiE "$prose_re"; then
  report "starts with a prose sentence — the model wrapped the artifact in an explanation"
fi
if printf '%s' "$tail_txt" | grep -qiE '(hope this helps|let me know|feel free to|semoga membantu|beri tahu saya|silakan sesuaikan)'; then
  report "ends with a prose sentence — there is text outside the artifact"
fi

# --- 2. code fence at the edge ---------------------------------------------
if printf '%s' "$head_txt" | head -1 | grep -qE '^[[:space:]]*```'; then
  report "starts with a \`\`\` code fence — strip the fence before use (or use a sentinel frame)"
fi

# --- 3. truncation signs ---------------------------------------------------
if [ -n "$(tail -c 1 "$file")" ]; then
  report "does not end with a newline — possibly truncated mid-stream"
fi
if printf '%s' "$tail_txt" | grep -qE '(\.\.\.|…|\[truncated\]|and so on|dan seterusnya)[[:space:]]*$'; then
  report "ends with an ellipsis or 'and so on' — the content was summarized, not completed"
fi

# --- 4. well-formatted guesses ---------------------------------------------
if grep -qE '(TODO|UNKNOWN|TIDAK_TAHU|FIXME|<content here>|<isi di sini>|placeholder|lorem ipsum)' "$file"; then
  report "contains a placeholder/UNKNOWN — the artifact is incomplete (honest, but not yet usable)"
fi

# --- 5. sentinel mode ------------------------------------------------------
if [ "$mode_sentinel" -eq 1 ]; then
  n_begin=$(grep -cF -- "$begin" "$file" || true)
  n_end=$(grep -cF -- "$end" "$file" || true)
  [ "$n_begin" -eq 0 ] && report "begin marker '$begin' is missing — the output did not follow the frame"
  [ "$n_end"   -eq 0 ] && report "end marker '$end' is missing — TRUNCATED, not finished"
  { [ "$n_begin" -gt 1 ] || [ "$n_end" -gt 1 ]; } && \
    report "found $n_begin/$n_end marker pairs — more than one artifact in a single call"
fi

# --- 6. json mode ----------------------------------------------------------
if [ "$mode_json" -eq 1 ]; then
  body="$file"
  if [ "$mode_sentinel" -eq 1 ]; then
    body=$(mktemp) || broken "mktemp failed"
    sed -n "/$(printf '%s' "$begin" | sed 's/[]\/$*.^[]/\\&/g')/,/$(printf '%s' "$end" | sed 's/[]\/$*.^[]/\\&/g')/p" \
      "$file" | sed '1d;$d' > "$body"
  fi
  if command -v python3 >/dev/null 2>&1; then
    err=$(python3 -c 'import json,sys;json.load(open(sys.argv[1]))' "$body" 2>&1) \
      || report "invalid JSON: $(printf '%s' "$err" | tail -1)"
  else
    report "python3 is unavailable — JSON could not be validated (do not treat this as a pass)"
  fi
  [ "$body" != "$file" ] && rm -f "$body"
fi

# --- 7. minimum length -----------------------------------------------------
if [ "$min_lines" -gt 0 ] && [ "$lines" -lt "$min_lines" ]; then
  report "only $lines lines, minimum $min_lines — likely summarized"
fi

if [ "$findings" -eq 0 ]; then
  [ "$quiet" -eq 1 ] || printf 'ACCEPTED (%s lines)\n' "$lines"
  exit 0
fi
[ "$quiet" -eq 1 ] || printf 'REJECTED (%s findings)\n' "$findings"
exit 1
