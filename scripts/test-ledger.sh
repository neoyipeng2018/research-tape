#!/usr/bin/env bash
# Self-check for the untick handler: unticking a box drops exactly that change, re-ticking
# restores it, and an edit that moves nothing pushes nothing. SPEC.md §7. The PR body under
# test is written by propose-taste.py's own formatter, so the two cannot drift apart.
set -u
cd "$(dirname "$0")/.."
fails=0
ok()  { echo "ok   $1"; }
bad() { echo "FAIL $1: $2"; fails=$((fails+1)); }

python3 - <<'PY'
import importlib.util, pathlib, subprocess, sys, tempfile

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

sys.path.insert(0, "scripts")
spec = importlib.util.spec_from_file_location("propose_taste", "scripts/propose-taste.py")
propose = importlib.util.module_from_spec(spec)
spec.loader.exec_module(propose)
import taste as taste_mod

BASE = pathlib.Path("taste.md").read_text()
PREFER = taste_mod.section_lines(BASE, "Prefer")
REJECT = taste_mod.section_lines(BASE, "Reject")

# A rewrite of the LAST Prefer bullet next to an add in the same section: the add anchors off
# that bullet, so an apply() that ran the rewrite first would land the add a line higher and an
# untick of the rewrite would move a line it never named.
CHANGES = [
    {"section": "Prefer", "op": "rewrite", "old": PREFER[-1], "evidence": [],
     "line": "- Evaluation itself: how a financial ML claim is shown to survive out of sample.",
     "argument": "The votes say so."},
    {"section": "Reject", "op": "drop", "old": REJECT[2], "line": "", "evidence": [],
     "argument": "The votes say so."},
    {"section": "Prefer", "op": "add", "old": "", "evidence": [],
     "line": "- Replications of a published financial ML result on data the authors did not pick.",
     "argument": "The votes say so."},
]

TALLY = {"votes": {"total": 9, "up": 6, "down": 3, "days": 5},
         "published": {"items": 40, "days": 30, "thin_days": 3, "empty_days": 1},
         "window": {"start": "2026-08-05", "end": "2026-09-03"}, "items": []}


def pr_body(changes):
    """The real PR body propose-taste.py would have written for these changes."""
    after = len(taste_mod.apply(BASE, changes).splitlines())
    return propose.body(changes, [], TALLY, ["**Replayed:** nothing changes."] * len(changes),
                        len(BASE.splitlines()), after, propose.CAP, {}, "o/r")


def untick(body, n):
    """Untick the n-th (1-based) ledger box, the way a reader does in the PR."""
    out, seen = [], 0
    for line in body.splitlines():
        if line.startswith("- [x] **"):
            seen += 1
            if seen == n:
                line = "- [ ]" + line[5:]
        out.append(line)
    return "\n".join(out) + "\n"


def run(body, taste_text, d):
    """One handler run over a body and the branch's current taste.md."""
    b, base, taste, com = (pathlib.Path(d, n) for n in ("body.md", "base.md", "taste.md", "c.md"))
    com.unlink(missing_ok=True)
    b.write_text(body); base.write_text(BASE); taste.write_text(taste_text)
    p = subprocess.run(["./scripts/ledger.py", "--body", b, "--base", base,
                        "--taste", taste, "--comment", com], capture_output=True, text=True)
    return p, taste.read_text(), (com.read_text() if com.exists() else "")


with tempfile.TemporaryDirectory() as d:
    full = pr_body(CHANGES)
    branch = taste_mod.apply(BASE, CHANGES)

    # --- an edit that moves nothing ------------------------------------------------------
    p, taste, com = run(full.replace("The votes say so.", "The votes say so, plainly."),
                        branch, d)
    check("an edit that changes nothing in the ledger writes no comment", com == "", repr(com[:80]))
    check("...and leaves taste.md alone", taste == branch)
    check("...and exits green", p.returncode == 0, p.stderr)

    # --- unticking one box ---------------------------------------------------------------
    p, taste, com = run(untick(full, 2), branch, d)
    want = taste_mod.apply(BASE, [CHANGES[0], CHANGES[2]])
    check("unticking a box removes exactly that change", taste == want,
          "".join(f"\n  {l}" for l in taste.splitlines() if l not in want.splitlines()))
    check("the other two changes survive",
          CHANGES[0]["line"] in taste and CHANGES[2]["line"] in taste)
    check("the dropped Reject line comes back", CHANGES[1]["old"] in taste)
    check("the comment names what was dropped",
          "Dropped" in com and CHANGES[1]["old"][2:] in com, repr(com))
    check("the comment names only what moved", com.count("- **") == 1, repr(com))
    # Exactly that change and no other line: the added bullet cannot drift because a rewrite
    # elsewhere in its section came off the table.
    diff = [l for l in taste.splitlines() if l not in branch.splitlines()]
    check("no other line moves", diff == [CHANGES[1]["old"]], repr(diff))

    # --- re-ticking it -------------------------------------------------------------------
    p, taste, com = run(full, want, d)
    check("re-ticking restores the change", taste == branch)
    check("the comment says it was restored",
          "Restored" in com and CHANGES[1]["old"][2:] in com, repr(com))

    # --- unticking everything ------------------------------------------------------------
    p, taste, com = run(full.replace("- [x] **", "- [ ] **"), branch, d)
    check("unticking every box lands the base file unchanged", taste == BASE)
    check("...and all three are named", com.count("- **") == 3, repr(com))
    # §6 rule 4: the box parser is liberal — `*`/`+` and either case of x are still ticks.
    p, taste, com = run(full.replace("- [x] **", "* [X] **"), branch, d)
    check("a `*` box in upper case is still ticked", taste == branch and com == "", repr(com))

    # --- a body this cannot act on -------------------------------------------------------
    for name, body in [
            ("whose ledger and sections disagree",
             "\n".join(l for l in full.splitlines() if not l.startswith("- [x] **"))),
            ("with no ledger at all", "Someone replaced the body with one line of prose.\n")]:
        p, taste, com = run(body, branch, d)
        check(f"a body {name} pushes nothing",
              p.returncode != 0 and taste == branch and com == "", p.stdout + p.stderr)

    # A rewrite's old line lives only in the diff block — the ledger carries rule text only.
    check("the ledger alone cannot say what a rewrite replaced",
          CHANGES[0]["old"][2:] not in "\n".join(
              l for l in full.splitlines() if l.startswith("- [")))

sys.exit(1 if fails else 0)
PY
[ $? -eq 0 ] || fails=$((fails+1))

# --- the workflow around it -------------------------------------------------------
echo
W=.github/workflows/taste-ledger.yml
has() { grep -qF -- "$2" "$W" && ok "$1" || bad "$1" "taste-ledger.yml lacks '$2'"; }
at()  { grep -n -- "$2" "$W" | head -1 | cut -d: -f1 | grep . || echo 0; }
before() { [ "$(at "$1" "$2")" -lt "$(at "$1" "$3")" ] && ok "$1" ||
           bad "$1" "'$2' does not precede '$3'"; }

has "fires on the body being edited" "types: [edited]"
has "only the taste PR"              "github.head_ref == 'taste'"
# `edited` fires on a merged PR too, and that force-push would rewrite what already landed.
has "and only while it is open"      "pull_request.state == 'open'"
has "the branch can be pushed"       "contents: write"
has "the comment can be posted"      "pull-requests: write"
has "runs are serialised, not cancelled" "cancel-in-progress: false"
has "the body is read from the API, not the payload" "gh pr view"
has "the base file is what it rebuilds from" "FETCH_HEAD:taste.md"
has "the handler runs"               "scripts/ledger.py"
has "nothing moved means nothing is pushed" "MOVED=no"
has "the branch is force-pushed"     "git push --force origin"
has "what was dropped is said on the PR" "gh pr comment"
before "the rewritten file is validated before it is pushed" "validate-taste.sh" "git push"
before "the push lands before the comment claims it did" "git push" "gh pr comment"

echo
[ "$fails" -eq 0 ] && echo "all ledger checks passed" || echo "FAILED ($fails)"
exit $((fails > 0))
