#!/usr/bin/env bash
# Self-check for the monthly loop: the permissions the taste PR needs, and the ordering
# monthly-taste.yml is only correct because of. SPEC.md §7-§8. The proposing itself is
# checked in test-propose-taste.sh; this file only checks the workflow around it.
set -u
cd "$(dirname "$0")/.."
W=.github/workflows/monthly-taste.yml
fails=0

ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails+1)); }
has() { grep -qF -- "$2" "$W" && ok "$1" || bad "$1" "monthly-taste.yml lacks '$2'"; }
at()  { grep -n -- "$2" "$W" | head -1 | cut -d: -f1 | grep . || echo 0; }
before() { [ "$(at "$1" "$2")" -lt "$(at "$1" "$3")" ] && ok "$1" ||
           bad "$1" "'$2' does not precede '$3'"; }

# --- the frame ------------------------------------------------------------------
has "fires monthly"          'cron: "0 23 1 * *"'
has "dispatch is the retry"  "workflow_dispatch:"
has "one run at a time"      "group: research-tape-monthly"

# `pull-requests: write` covers POST /pulls and nothing else — the branch still has to be
# pushed, which is `contents: write` (§8).
has "the branch can be pushed" "contents: write"
has "the PR can be raised"     "pull-requests: write"
has "the no-change line can be posted" "issues: write"
# Off by default, and `gh pr create` 403s without it. A comment is the only place this can live.
has "the repo setting is named" "Allow GitHub"

# --- the shape of the run --------------------------------------------------------
for s in tally-votes propose-taste validate-taste; do
  has "step: $s" "scripts/$s"
done
before "the votes are tallied before anything is proposed" "tally-votes.py" "propose-taste.py"
before "the bar guard precedes the judge"   "PROPOSE=no" "propose-taste.py"
before "the open PR is read before proposing" "gh pr list" "propose-taste.py"
before "the amended taste.md is validated before it is pushed" "validate-taste.sh" "git push"
before "the branch is pushed before the PR is raised" "git push --force" "gh pr create --base"
has "auth probe has its own timeout" "timeout -k 10 120"
has "the judge step is bounded"      "timeout-minutes: 30"

# --- one open taste PR, force-pushed -----------------------------------------------
has "one branch is the identity"  "BRANCH: taste"
has "the open PR is found by branch, not by label" '--head "$BRANCH" --state open'
has "the same branch is force-pushed" 'git push --force origin "$BRANCH"'
grep -qF 'gh pr create' "$W" && grep -qF 'gh pr edit' "$W" &&
  ok "an open PR is rewritten and a new one is only raised when there is none" ||
  bad "one open PR" "the create/edit pair is not both there"
# The edit and the create have to be the two arms of one branch, or a second PR gets raised.
awk '/if \[ -n "\$PR" \]/{p=1} p&&/gh pr create/{print "in-else"; exit}' "$W" | grep -q in-else &&
  ok "the create arm is guarded by there being no open PR" ||
  bad "one open PR" "gh pr create is not inside the no-open-PR branch"
before "what was retired is said before the body that drops it" "gh pr comment" "gh pr edit"
has "the retirement comment is what propose-taste wrote" 'retired.md'
# §9: a PR sitting unmerged breaks nothing, but the force-push says how long it has sat.
has "the stale PR gets its line" "had sat unmerged for"
has "the line names the PR"      'PR_DAYS'

# --- the note, and saying nothing twice ---------------------------------------------
has "the note goes on the day's vote issue" "gh issue comment"
has "the note is not repeated on a rerun"   'grep -qF -- "$(head -1'
before "the note is posted last" "gh pr create --base" "gh issue comment"

# --- taste.md and nothing else -------------------------------------------------------
grep -qF 'git add taste.md' "$W" && ok "only taste.md is staged" ||
  bad "taste.md and nothing else" "the commit stages more than taste.md"
grep -qE 'git add -A|git add \.' "$W" && bad "taste.md and nothing else" "a blanket git add" ||
  ok "nothing else can ride along in the commit"

[ "$fails" -eq 0 ] && echo "all monthly checks passed" || echo "$fails check(s) failed"
exit $((fails > 0))
