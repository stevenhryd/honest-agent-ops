#!/usr/bin/env bash
# audit-job.sh — pass verdict on an unattended job from EVIDENCE, not from its own status.
#
# OUTPUT CONTRACT (do not change — this is what makes the tool safe to run from cron):
#   stdout has content = FINDINGS EXIST (empty run / no evidence)
#   stdout empty       = no findings (the job is proven to have worked)
#   exit 0             = the tool judged successfully — INCLUDING when there are findings
#   exit 2             = THE TOOL ITSELF IS BROKEN (bad arguments, missing paths, invalid date)
# Stacking "findings exist" onto the exit code creates a feedback loop: the scheduler marks the job
# `error`, tomorrow's audit reads that failure as an additional finding, red forever.
#
# Usage:
#   audit-job.sh NAME --evidence 'GLOB|DIR' [--evidence ...] --since 'SPEC' [--min N] [--verbose]
#
#   --evidence  file/glob/directory whose CONTENT should be growing. May be repeated.
#               Globs MUST be quoted so the shell does not expand them first.
#   --since     anything `date -d` understands: '6 hours ago', 'today 15:00', ISO 8601.
#               Set it to the START time of the run being judged.
#   --min       how many new artifacts are required to count as working (default 1).
#   --verbose   print the verdict even when there are no findings (for manual runs).
#
# Example:
#   audit-job.sh mentor-reflection --evidence '~/.hermes/knowledge/*.md' --since '2026-08-31 15:00'
set -uo pipefail

name=""; since=""; min=1; verbose=0; evidence=()

broken() { printf 'TOOL BROKEN (%s): %s\n' "${name:-audit-job}" "$1" >&2; exit 2; }

[ $# -ge 1 ] || broken "no arguments. Usage: audit-job.sh NAME --evidence GLOB --since SPEC"
name="$1"; shift
case "$name" in -*) broken "the first argument must be the job NAME, not the option '$name'";; esac

while [ $# -gt 0 ]; do
  case "$1" in
    --evidence) [ $# -ge 2 ] || broken "--evidence needs a value"; evidence+=("$2"); shift 2 ;;
    --since)    [ $# -ge 2 ] || broken "--since needs a value";    since="$2";       shift 2 ;;
    --min)      [ $# -ge 2 ] || broken "--min needs a value";      min="$2";         shift 2 ;;
    --verbose)  verbose=1; shift ;;
    *) broken "unknown option: $1" ;;
  esac
done

[ "${#evidence[@]}" -gt 0 ] || broken "at least one --evidence is required (a job with no output contract cannot be judged)"
[ -n "$since" ]             || broken "--since is required (the start time of the run being judged)"
case "$min" in ''|*[!0-9]*) broken "--min must be an integer, got '$min'";; esac

threshold=$(date -d "$since" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || broken "--since not understood by date: '$since'"

fresh=0; total=0; newest=""; missing=()

for pattern in "${evidence[@]}"; do
  # ~ is not expanded inside a quoted string — do it by hand.
  case "$pattern" in "~"/*) pattern="$HOME${pattern#\~}";; esac

  if [ -d "$pattern" ]; then
    root="$pattern"; filter=(-type f)
  elif [ -e "$pattern" ]; then
    root=$(dirname -- "$pattern"); filter=(-type f -path "$pattern")
  else
    case "$pattern" in
      *[*?[]*) # wildcard present: root = longest directory prefix that actually exists
        root="${pattern%%/\**}"; [ "$root" = "$pattern" ] && root=$(dirname -- "$pattern")
        while [ -n "$root" ] && [ ! -d "$root" ]; do
          parent=$(dirname -- "$root"); [ "$parent" = "$root" ] && break; root="$parent"
        done
        filter=(-type f -path "$pattern") ;;
      *) # a plain path that genuinely does not exist — do not walk up to its parent
        missing+=("$pattern"); continue ;;
    esac
  fi

  if [ ! -d "$root" ]; then missing+=("$pattern"); continue; fi

  # find can exit != 0 merely because of "Permission denied" on an unrelated branch; that is not a broken tool.
  listing=$(find "$root" "${filter[@]}" -printf '%T@ %TY-%Tm-%Td %TH:%TM %p\n' 2>/dev/null)
  if [ -n "$listing" ]; then t=$(printf '%s\n' "$listing" | wc -l); else t=0; fi
  n=$(find "$root" "${filter[@]}" -newermt "$threshold" -printf 'x\n' 2>/dev/null | wc -l)
  fresh=$((fresh + n)); total=$((total + t))

  m=$(printf '%s\n' "$listing" | sort -rn | head -1)
  if [ -n "$m" ]; then
    if [ -z "$newest" ] || [ "${m%% *}" \> "${newest%% *}" ]; then newest="$m"; fi
  fi
done

[ "${#missing[@]}" -eq "${#evidence[@]}" ] && broken "not one evidence path exists: ${missing[*]}"

trace="${newest#* }"
[ -n "$trace" ] || trace="(no files at all under the evidence paths)"

if [ "$fresh" -ge "$min" ]; then
  noun="artifacts"; [ "$fresh" -eq 1 ] && noun="artifact"
  [ "$verbose" -eq 1 ] && printf '%s: WORKING — %s new %s since %s (newest: %s)\n' \
    "$name" "$fresh" "$noun" "$threshold" "$trace"
  exit 0
fi

if [ "$total" -eq 0 ]; then
  printf '%s: NO EVIDENCE — the evidence paths are completely empty. This job has never produced anything.\n' "$name"
else
  printf '%s: EMPTY RUN — 0 new artifacts since %s (needed %s). Newest artifact: %s\n' \
    "$name" "$threshold" "$min" "$trace"
fi
[ "${#missing[@]}" -gt 0 ] && printf '%s: note — evidence path does not exist: %s\n' "$name" "${missing[*]}"
exit 0
