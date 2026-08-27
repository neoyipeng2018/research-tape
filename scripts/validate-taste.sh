#!/usr/bin/env bash
# Refuse a taste.md the rest of the loop cannot read. SPEC.md §4.
# Two call sites: first step of the daily run, and the taste-check PR gate.
set -u
F=${1:-taste.md}
die() { echo "taste.md invalid: $*" >&2; exit 1; }

[ -f "$F" ] || die "$F not found"

n=$(grep -c '' "$F")   # not wc -l: a missing final newline would hide a line
[ "$n" -le 40 ] || die "hard cap is 40 lines, found $n"

# Sections: all four, in fixed order, nothing else at heading level.
found=$(grep '^## ' "$F" | tr '\n' '|')
[ "$found" = "## Queries|## Prefer|## Reject|## Bar|" ] ||
  die "sections must be exactly '## Queries, ## Prefer, ## Reject, ## Bar' in that order, found '${found%|}'"

section() { awk -v s="## $1" '$0==s{p=1;next} /^## /{p=0} p' "$F"; }

# Queries: one arxiv line (continuations indented) and one ssrn line.
q=$(section Queries)
arxiv=$(printf '%s\n' "$q" | awk '/^arxiv: /{p=1;print;next} /^[^ ]/{p=0} p' | tr -d '\n')
[ -n "$arxiv" ] || die "## Queries has no 'arxiv: ' line"
[ "$(printf '%s\n' "$q" | grep -c '^ssrn: ')" -eq 1 ] || die "## Queries needs exactly one 'ssrn: ' line"
bad=$(printf '%s\n' "$q" | grep -vn '^\(arxiv: \|ssrn: \|  \|$\)' | head -1)
[ -z "$bad" ] || die "## Queries takes only 'name: value' lines and indented continuations, got '$bad'"

# Balanced, not merely counted: depth must never go negative and must land on zero,
# with parens inside quoted phrases ignored.
awk -v s="$arxiv" 'BEGIN {
  for (i = 1; i <= length(s); i++) {
    c = substr(s, i, 1)
    if (c == "\"") q = !q
    else if (!q && c == "(") d++
    else if (!q && c == ")") { if (--d < 0) exit 2 }
  }
  exit q ? 3 : (d ? 4 : 0)
}'
case $? in
  2) die "arxiv query closes a paren that was never opened" ;;
  3) die "arxiv query has an unclosed double quote" ;;
  4) die "arxiv query leaves a paren unclosed" ;;
esac

# Prefer / Reject: at least one '- ' bullet each, passed to the judge verbatim.
for s in Prefer Reject; do
  [ "$(section "$s" | grep -c '^- ')" -ge 1 ] || die "## $s has no '- ' bullet lines"
done

# Bar: exactly threshold and cap, both integers.
bar=$(section Bar)
bad=$(printf '%s\n' "$bar" | grep -vn '^\(threshold: .*\|cap: .*\|$\)' | head -1)
[ -z "$bad" ] || die "## Bar takes only 'threshold:' and 'cap:' lines, got '$bad'"
for k in threshold cap; do
  v=$(printf '%s\n' "$bar" | sed -n "s/^$k: //p")
  [ -n "$v" ] || die "## Bar is missing '$k:'"
  case $v in ''|*[!0-9]*) die "## Bar '$k: $v' is not an integer";; esac
done

echo "$F ok ($n lines)"
