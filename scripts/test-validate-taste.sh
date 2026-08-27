#!/usr/bin/env bash
# Self-check for validate-taste.sh: the shipped file passes, each broken rule fails
# with a message naming that rule.
set -u
cd "$(dirname "$0")/.."
V=scripts/validate-taste.sh
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0

check() { # check <name> <file> [expected message substring]
  if "$V" "$2" >"$TMP/out" 2>&1; then got=pass; else got=fail; fi
  want=fail; [ $# -eq 2 ] && want=pass
  if [ "$got" != "$want" ]; then
    echo "FAIL $1 (expected $want, got $got): $(cat "$TMP/out")"; fails=$((fails+1))
  elif [ $# -eq 3 ] && ! grep -qi -- "$3" "$TMP/out"; then
    echo "FAIL $1 (message did not name the rule): $(cat "$TMP/out")"; fails=$((fails+1))
  else echo "ok   $1"; fi
}
mut() { # mut <name> <command...>  -> writes and echoes $TMP/<name>, dies if the mutation fails
  local n=$1; shift
  "$@" taste.md > "$TMP/$n" || { echo "broken fixture: $n" >&2; exit 1; }
  echo "$TMP/$n"
}

check "shipped taste.md" taste.md

check "missing section"    "$(mut missing  sed '/^## Reject$/d')"           "sections must be"
check "non-integer bar"    "$(mut badbar   sed 's/^threshold: 7$/threshold: seven/')" "not an integer"
check "missing cap"        "$(mut nocap    sed '/^cap: 6$/d')"              "missing 'cap:'"
check "stray Bar key"      "$(mut barjunk  sed 's/^cap: 6$/cap: 6\
weight: 3/')"                                                               "## Bar takes only"
check "stray Queries line" "$(mut qjunk    sed 's/^ssrn: /junk\
ssrn: /')"                                                                  "## Queries takes only"
check "missing ssrn query" "$(mut nossrn   sed '/^ssrn: /d')"               "ssrn"
check "zero Prefer lines"  "$(mut noprefer awk '/^## Prefer$/{p=1} /^## Reject$/{p=0} !(p && /^- /)')" "Prefer has no"
check "zero Reject lines"  "$(mut noreject awk '/^## Reject$/{p=1} /^## Bar$/{p=0} !(p && /^- /)')"    "Reject has no"

# arXiv query: counted-but-unbalanced must fail too, not just miscounted.
check "unclosed paren"     "$(mut parens   sed 's/^arxiv: (/arxiv: ((/')"    "unclosed"
check "paren never opened" "$(mut parens2  sed -e 's/^arxiv: (/arxiv: )/' -e 's/")))$/"))(/')" "never opened"
check "unclosed quote"     "$(mut quotes   sed 's/abs:"financial"/abs:"financial/')" "double quote"

# Section order: all four present, wrong order.
b=$(grep -n '^## Bar$' taste.md | cut -d: -f1)
{ tail -n +"$b" taste.md; head -n $((b-1)) taste.md; } > "$TMP/order"
check "sections out of order" "$TMP/order" "in that order"

# The cap counts lines, including a last line with no newline of its own.
{ cat taste.md; seq 10 | sed 's/^/- filler /'; printf -- '- no trailing newline'; } > "$TMP/long"
check "over 40 lines" "$TMP/long" "hard cap is 40 lines"

[ "$fails" -eq 0 ] && echo "all ok" || { echo "$fails failing"; exit 1; }
