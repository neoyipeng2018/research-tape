#!/usr/bin/env bash
# Self-check for vote-issue.py: two boxes an item, the hazards of SPEC.md §6, quiet days
# and the status lines a degraded lane leaves behind.
set -u
cd "$(dirname "$0")/.."
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fails=0

ok()   { echo "ok   $1"; }
bad()  { echo "FAIL $1: $2"; fails=$((fails+1)); }
has()  { grep -qF -- "$2" "$TMP/body.md" && ok "$1" || bad "$1" "missing '$2'"; }
hasnt(){ grep -qF -- "$2" "$TMP/body.md" && bad "$1" "found '$2'" || ok "$1"; }

body() { # body <fixture> [extra args...] — render that tape into $TMP/body.md
  local f=$1; shift
  scripts/vote-issue.py --tape "scripts/fixtures/$f" "$@" >"$TMP/body.md" 2>"$TMP/err" ||
    { bad "vote-issue $f" "$(cat "$TMP/err")"; return 1; }
}

# --- a published day ------------------------------------------------------------
body tape-mixed.json || exit 1
has "the day is named"     "2026-08-20"
has "the count is stated"  "3 of 34 scanned"
has "the paper link is in the heading" "### [Converting Expert Deliberation"
has "arXiv up box"   "- [ ] 👍 more like this <!--v:up:arxiv:2608.18911-->"
has "arXiv down box" "- [ ] 👎 less like this <!--v:down:arxiv:2608.18911-->"
has "SSRN up box"    "<!--v:up:ssrn:10.2139/ssrn.7309901-->"

n=$(grep -c '^- \[ \] ' "$TMP/body.md")
[ "$n" -eq 6 ] && ok "two unticked boxes for each of the three items" ||
  bad "box count" "got $n vote lines, expected 6"
grep -q '^- \[[xX]\]' "$TMP/body.md" && bad "never pre-ticked" "a box arrives ticked" ||
  ok "no box arrives ticked"
grep -n '^- \[\]' "$TMP/body.md" && bad "documented checkbox form" "a box lost its space" ||
  ok "every box is the documented '- [ ] ' form"

# The key rides a *trailing* comment: a leading one destroys the checkbox (§6 rule 1).
grep -q '^- \[ \] <!--' "$TMP/body.md" && bad "trailing comment" "a comment leads a vote line" ||
  ok "the key comment trails the line"
grep '^- \[ \] ' "$TMP/body.md" | grep -qv -- '-->$' &&
  bad "trailing comment" "a vote line does not end in its key comment" ||
  ok "every vote line ends in its key comment"

# §6 rule 3: an issue reference on a task-list line auto-ticks and fabricates a vote.
grep '^- \[ \] ' "$TMP/body.md" | grep -qE '#[0-9]|github\.com/[^ ]*/(issues|pull)/' &&
  bad "no cross-reference on a vote line" "a vote line references an issue" ||
  ok "no vote line carries an issue reference or issue URL"

# --- a quiet day still opens ----------------------------------------------------
body tape-quiet.json || exit 1
has   "the quiet day is named" "2026-08-22"
has   "zero-cleared line"      "Nothing cleared the bar today"
has   "what was scanned"       "0 of 27 scanned"
hasnt "no checkboxes at all"   "- [ ]"

# --- degraded lanes are the status surface --------------------------------------
printf 'arXiv lane unreachable: URLError: timed out\nssrn lane returned nothing usable\n' >"$TMP/notes.md"
body tape-quiet.json --notes "$TMP/notes.md" || exit 1
has "the degraded lane is named" "arXiv lane unreachable: URLError: timed out"
has "both notes land"            "ssrn lane returned nothing usable"
body tape-mixed.json --notes "$TMP/does-not-exist.md" ||
  bad "a missing notes file" "exited non-zero"
hasnt "no note section without notes" "---"

# --- the hazard guard bites, rather than shipping a fabricated vote ---------------
python3 -c 'import json,sys
t=json.load(open("scripts/fixtures/tape-mixed.json"))
t["items"][0]["key"]="see #29"
json.dump(t,open(sys.argv[1],"w"))' "$TMP/poison.json"
if scripts/vote-issue.py --tape "$TMP/poison.json" >"$TMP/out" 2>/dev/null; then
  bad "an issue reference in a key" "exited 0"
elif [ -s "$TMP/out" ]; then bad "an issue reference in a key" "wrote a body anyway"
else ok "an issue reference in a key fails and writes nothing"; fi

# A note is appended text, but §6 rule 4's liberal forms are task lists too: a `*`-bulleted
# status line naming a PR is a fabricated vote if it ever ships.
printf '* [ ] taste PR #31 has sat for 12 days\n' >"$TMP/poison-notes.md"
if scripts/vote-issue.py --tape scripts/fixtures/tape-quiet.json --notes "$TMP/poison-notes.md" \
     >/dev/null 2>&1; then
  bad "a '*' task line naming a PR" "exited 0"
else ok "the guard covers '*' and '+' task lines, not just '-'"; fi

# --- a markdown-hostile title stays inside its link -------------------------------
python3 -c 'import json,sys
t=json.load(open("scripts/fixtures/tape-mixed.json"))
t["items"][0]["title"]="Brackets [in] a title"
json.dump(t,open(sys.argv[1],"w"))' "$TMP/brackets.json"
scripts/vote-issue.py --tape "$TMP/brackets.json" >"$TMP/body.md" 2>/dev/null
has "brackets in a title are escaped" "Brackets \[in\] a title"

[ "$fails" -eq 0 ] && echo "all vote-issue checks passed" || echo "$fails check(s) failed"
exit $((fails > 0))
