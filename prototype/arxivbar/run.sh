#!/bin/bash
# PROTOTYPE, throwaway. Judge each day 3x (pass 1 only), median wins.
set -e
cd /Users/boo/research-tape
for d in 2026-08-12 2026-08-13 2026-08-14 2026-08-17 2026-08-18; do
  cp prototype/arxivbar/cand_$d.json prototype/candidates.json
  for r in 1 2 3; do
    out=prototype/arxivbar/scored_${d}_r$r.json
    [ -f "$out" ] && continue
    P1ONLY=1 python3 prototype/judge.py "${TASTE:-prototype/taste.md}" "$out"
    echo "done $d r$r"
  done
done
