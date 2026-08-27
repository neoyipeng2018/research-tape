#!/usr/bin/env bash
# Self-check for render.py: the four day shapes from SPEC.md §5, and a valid feed.
set -u
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0

ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1: $2"; fails=$((fails+1)); }
has()  { grep -qF -- "$2" "$TMP/out/index.html" && ok "$1" || bad "$1" "missing '$2'"; }
hasnt(){ grep -qF -- "$2" "$TMP/out/index.html" && bad "$1" "found '$2'" || ok "$1"; }

fresh() { rm -rf "$TMP/tape" "$TMP/out"; mkdir -p "$TMP/tape" "$TMP/out"; }

render() { # render <fixture...> — a tape dir of those fixtures, filed under their own dates
  fresh
  for f; do
    d=$(sed -n 's/.*"date": "\([0-9-]*\)".*/\1/p' "scripts/fixtures/$f")
    cp "scripts/fixtures/$f" "$TMP/tape/$d.json"
  done
  scripts/render.py --tape-dir "$TMP/tape" --out "$TMP/out" >"$TMP/log" 2>&1 ||
    { bad "render $*" "$(cat "$TMP/log")"; return 1; }
}

# --- variant A frame, mixed day ------------------------------------------------
render tape-full.json tape-mixed.json || exit 1
has  "masthead"        "Research Tape"
has  "date of the tape shown" "Thursday 20 August 2026"
has  "meta line"       "3 of 34 scanned · arXiv + SSRN"
has  "archive link"    ">archive<"
has  "rss link"        "feed.xml"
has  "two-digit index" ">01<"
has  "source prefix on a mixed day" "arXiv —"
has  "SSRN prefix on a mixed day"   "SSRN —"
has  "claim leads the row" "Investment-committee transcripts yield tradable signals"
has  "title is a link"     'href="https://arxiv.org/abs/2608.18911"'
hasnt "no JavaScript"      "<script"
srcs=$(grep -o 'class="src">[A-Za-z]*' "$TMP/out/index.html" | sed 's/.*>//' | tr '\n' ' ')
[ "$srcs" = "arXiv SSRN arXiv " ] && ok "rows keep tape order, not grouped by source" ||
  bad "no source grouping" "row sources were '$srcs'"

# --- one-source day: no stray prefixes ----------------------------------------
render tape-full.json
hasnt "one-source day has no prefix" "SSRN —"
hasnt "full day has no quiet line"   "Nothing else cleared the bar"
has   "ampersand escaped"            "Errors &amp; Endogenous"

# --- thin day and zero-item day -----------------------------------------------
render tape-thin.json
has "thin day acknowledged" "Nothing else cleared the bar today."
render tape-quiet.json
has "zero-item day acknowledged" "Nothing else cleared the bar today."
has "zero-item meta"             "0 of 27 scanned"

# --- feed.xml ------------------------------------------------------------------
render tape-full.json tape-mixed.json tape-thin.json tape-quiet.json
python3 - "$TMP/out/feed.xml" <<'PY' || fails=$((fails+1))
import sys, xml.etree.ElementTree as ET
r = ET.parse(sys.argv[1]).getroot()
assert r.tag == "rss" and r.get("version") == "2.0", "not RSS 2.0"
ch = r.find("channel")
for t in ("title", "link", "description"): assert ch.findtext(t), f"channel missing {t}"
items = ch.findall("item")
assert len(items) == 10, f"expected 10 items, got {len(items)}"
i = items[0]
assert i.findtext("title") and i.findtext("link") and i.findtext("description")
assert i.findtext("guid") == "2608.20114", i.findtext("guid")
assert i.findtext("pubDate").startswith("Fri, 21 Aug 2026"), i.findtext("pubDate")
print("ok   feed.xml is RSS 2.0, newest tape first")
PY

# --- the 30-tape window ---------------------------------------------------------
fresh
for d in $(python3 -c 'import datetime;print(*(datetime.date(2026,6,20)+datetime.timedelta(n) for n in range(40)))'); do
  sed "s/2026-08-21/$d/" scripts/fixtures/tape-thin.json > "$TMP/tape/$d.json"
done
scripts/render.py --tape-dir "$TMP/tape" --out "$TMP/out" >/dev/null 2>&1
n=$(grep -c '<item>' "$TMP/out/feed.xml")
[ "$n" -eq 30 ] && ok "feed covers the last 30 tapes" || bad "feed window" "got $n items"
grep -q '2026-06-' "$TMP/out/feed.xml" && bad "feed window" "included a 31st-oldest tape" || ok "feed drops older tapes"

# --- a malformed tape is a dark day, not a wrong page (SPEC.md §9) ----------------
fresh
python3 -c 'import json,sys;t=json.load(open("scripts/fixtures/tape-full.json"));del t["scanned"];json.dump(t,open(sys.argv[1],"w"))' "$TMP/tape/2026-08-19.json"
if scripts/render.py --tape-dir "$TMP/tape" --out "$TMP/out" >/dev/null 2>&1; then
  bad "tape missing 'scanned'" "exited 0"
elif [ -n "$(ls -A "$TMP/out")" ]; then bad "tape missing 'scanned'" "wrote files"
else ok "tape missing 'scanned' fails and writes nothing"; fi

# --- no tape at all: write nothing, exit non-zero --------------------------------
fresh
if scripts/render.py --tape-dir "$TMP/tape" --out "$TMP/out" >/dev/null 2>&1; then
  bad "empty tape dir" "exited 0"
elif [ -n "$(ls -A "$TMP/out")" ]; then bad "empty tape dir" "wrote files"
else ok "empty tape dir fails and writes nothing"; fi

[ "$fails" -eq 0 ] && echo "all render checks passed" || echo "$fails check(s) failed"
exit $((fails > 0))
