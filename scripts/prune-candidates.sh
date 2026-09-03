#!/usr/bin/env bash
# Drop candidate files older than the 30-day window. SPEC.md §8.
# Filename dates, not mtime: a fresh checkout stamps every file with the checkout time.
# The window matches dedup.py's, so pruning never blinds the fingerprint check.
set -u
DIR=${1:-candidates}
DAYS=30   # dedup.py's WINDOW_DAYS. Two names for one window, and they have to agree.
cut=$(python3 -c "import datetime;print(datetime.date.today()-datetime.timedelta($DAYS))")
[ -n "$cut" ] || { echo "prune: could not compute the $DAYS-day cutoff" >&2; exit 1; }

n=0
for f in "$DIR"/*.json; do
  [ -e "$f" ] || continue          # no candidates yet: nothing to prune
  d=$(basename "$f" .json)
  [[ "$d" < "$cut" ]] || continue  # ISO dates sort as strings
  rm -f "$f"
  n=$((n+1))
done
echo "pruned $n candidate file(s) older than $cut"
