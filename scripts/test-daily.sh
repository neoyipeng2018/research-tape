#!/usr/bin/env bash
# Self-check for the daily loop: the prune window, and the ordering guarantees daily.yml
# is only correct because of. SPEC.md §8-§9.
set -u
cd "$(dirname "$0")/.."
W=.github/workflows/daily.yml
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails+1)); }
has() { grep -qF -- "$2" "$W" && ok "$1" || bad "$1" "daily.yml lacks '$2'"; }
at()  { grep -n -- "$2" "$W" | head -1 | cut -d: -f1 | grep . || echo 0; }  # 0 when absent
before() { # before <name> <earlier-pattern> <later-pattern>
  [ "$(at "$1" "$2")" -lt "$(at "$1" "$3")" ] && ok "$1" || bad "$1" "'$2' does not precede '$3'"
}

# --- the workflow frame --------------------------------------------------------
has "runs on a schedule"        'cron: "0 22 * * *"'
has "dispatch is the retry"     "workflow_dispatch:"
has "one run at a time"         "group: research-tape-daily"
has "30-minute job timeout"     "timeout-minutes: 30"
has "auth probe has its own timeout" "timeout -k 10 120"
[ "$(grep -c 'timeout-minutes: 15' "$W")" -ge 1 ] && ok "judge steps are bounded" ||
  bad "judge steps are bounded" "no per-step timeout on a judge step"

# The push fires no workflow, so every step the tape depends on lives in this job.
grep -qE '^[[:space:]]+(push|pull_request):' "$W" && bad "no push trigger" "daily.yml triggers on push" ||
  ok "nothing here waits on a push-triggered workflow"
for s in validate-taste fetch-arxiv fetch-ssrn dedup triage claim prune-candidates render; do
  has "step: $s" "scripts/$s"
done

# --- ordering, which is the whole failure contract -----------------------------
before "taste is validated before any fetch" "validate-taste.sh" "fetch-arxiv.py"
before "both lanes down exits before dedup"  "both lanes returned nothing" "dedup.py"
before "prune runs before the commit"        "prune-candidates.sh" "git add"
before "render runs before the commit"       "render.py" "git add"

# --- candidates have to survive the run to be worth pruning --------------------
grep -qE '^candidates/' .gitignore && bad "candidates are committed" "candidates/ is gitignored" ||
  ok "candidates are committed, so dedup's 30-day window has something to read"

# --- the prune window ----------------------------------------------------------
mkdir -p "$TMP/candidates"
day() { python3 -c "import datetime,sys;print(datetime.date.today()-datetime.timedelta(int(sys.argv[1])))" "$1"; }
for n in 0 1 29 30 31 400; do : > "$TMP/candidates/$(day $n).json"; done
: > "$TMP/candidates/not-a-date.json"
scripts/prune-candidates.sh "$TMP/candidates" >/dev/null || bad "prune runs" "exited non-zero"
kept=$(ls "$TMP/candidates" | wc -l | tr -d ' ')
[ "$kept" -eq 5 ] && ok "prune keeps the last 30 days" || bad "prune window" "kept $kept of 7, expected 5"
[ -f "$TMP/candidates/$(day 30).json" ] && ok "the boundary day is kept" ||
  bad "prune window" "dropped the 30-day-old file the dedup window still reads"
[ -f "$TMP/candidates/$(day 31).json" ] && bad "prune window" "kept a 31-day-old file" ||
  ok "older days are dropped"
[ -f "$TMP/candidates/not-a-date.json" ] && ok "a file that is not a day is left alone" ||
  bad "prune window" "deleted a file it could not date"

rm -rf "$TMP/candidates"; mkdir -p "$TMP/candidates"
scripts/prune-candidates.sh "$TMP/candidates" >/dev/null &&
  ok "an empty candidates dir prunes nothing and exits 0" ||
  bad "empty candidates dir" "exited non-zero"

[ "$fails" -eq 0 ] && echo "all daily checks passed" || echo "$fails check(s) failed"
exit $((fails > 0))
