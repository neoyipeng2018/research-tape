#!/usr/bin/env bash
# Self-check for propose-taste.py: the 3-change budget, the per-line 3-vote bar, the ledger
# and its auto-tick hazard, demotion-only replay, and what comes off the table when a taste PR
# is already open. SPEC.md §7. The judge is a stub `claude` on PATH replaying scripted envelopes.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os, pathlib, re, shutil, subprocess, sys, tempfile

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

STUB = r'''#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB"]
n = len(os.listdir(os.path.join(d, "calls")))
open(os.path.join(d, "calls", str(n)), "w").write(sys.stdin.read())
plan = json.load(open(os.path.join(d, "plan.json")))
r = plan[min(n, len(plan) - 1)]
sys.stdout.write(r.get("stdout", ""))
sys.exit(r.get("exit", 0))
'''

TASTE = pathlib.Path("taste.md").read_text()
PREFER = [l for l in TASTE.splitlines() if l.startswith("- ")][:5]
REJECT = [l for l in TASTE.splitlines() if l.startswith("- ")][5:]
DROP_REJECT = "- Single-country or single-sector empirics with no transferable method."
assert DROP_REJECT in REJECT, "fixture drifted from taste.md"

TAPES = ["tape-full.json", "tape-mixed.json", "tape-thin.json", "tape-quiet.json"]


def envelope(**structured):
    return {"stdout": json.dumps({"type": "result", "subtype": "success", "is_error": False,
                                  "result": "done", "structured_output": structured})}


def proposal(changes, retired=(), seen=("Deep hedging — 2 👍, under the 3-vote bar.",)):
    return envelope(changes=list(changes), retired=list(retired), seen=list(seen))


def replay_scores(scores):
    """One replay run: id -> score over the key-sorted published candidates."""
    return envelope(scores=[{"id": i, "score": s, "why": "w"} for i, s in scores])


def world(d):
    """A window: four tape days, the candidate records behind them, a tally over their keys."""
    tape, cand = pathlib.Path(d, "tape"), pathlib.Path(d, "candidates")
    tape.mkdir(); cand.mkdir()
    shutil.copy("taste.md", pathlib.Path(d, "taste.md"))
    keys, records = [], []
    for f in TAPES:
        t = json.loads(pathlib.Path("scripts/fixtures", f).read_text())
        pathlib.Path(tape, t["date"] + ".json").write_text(json.dumps(t))
        for it in t["items"]:
            keys.append((it["key"], it["source"]))
            records.append({"key": it["key"], "source": it["source"], "link": it["link"],
                            "title": it["title"], "abstract": "An abstract about " + it["title"],
                            "score": 8, "why": "w"})
    pathlib.Path(cand, "2026-08-20.json").write_text(json.dumps(records))
    items = [{"key": k, "source": s, "up": 2, "down": 1,
              "days": [{"date": "2026-08-20", "issue": 100 + i}]}
             for i, (k, s) in enumerate(keys)]
    tally = {"window": {"start": "2026-07-26", "end": "2026-08-25"},
             "published": {"days": 4, "items": 10, "thin_days": 2, "empty_days": 1},
             "votes": {"up": 20, "down": 10, "total": 30, "days": 4},
             "items": items, "clears_bar": True, "note_issue": 120}
    pathlib.Path(d, "tally.json").write_text(json.dumps(tally))
    return [k for k, _ in keys]


def run(plan, open_pr=None):
    """(returncode, stderr, files written, prompts seen)."""
    d = tempfile.mkdtemp()
    keys = world(d)
    os.makedirs(os.path.join(d, "calls"))
    json.dump(plan, open(os.path.join(d, "plan.json"), "w"))
    with open(os.path.join(d, "claude"), "w") as f:
        f.write(STUB)
    os.chmod(os.path.join(d, "claude"), 0o755)
    args = []
    if open_pr is not None:
        pathlib.Path(d, "open-pr.md").write_text(open_pr)
        args = ["--open-pr", os.path.join(d, "open-pr.md")]
    p = subprocess.run(
        [sys.executable, "scripts/propose-taste.py", "--tally", os.path.join(d, "tally.json"),
         "--taste", os.path.join(d, "taste.md"), "--tape-dir", os.path.join(d, "tape"),
         "--candidates-dir", os.path.join(d, "candidates"), "--repo", "o/r",
         "--body", os.path.join(d, "pr.md"), "--title", os.path.join(d, "title.txt"),
         "--retired", os.path.join(d, "retired.md"), "--note", os.path.join(d, "note.md")] + args,
        capture_output=True, text=True,
        env=dict(os.environ, STUB=d, PATH=d + os.pathsep + os.environ["PATH"]))
    read = lambda n: pathlib.Path(d, n).read_text() if pathlib.Path(d, n).exists() else None
    prompts = [open(os.path.join(d, "calls", n)).read()
               for n in sorted(os.listdir(os.path.join(d, "calls")), key=int)]
    return p.returncode, p.stderr, {n: read(n) for n in
                                    ("pr.md", "title.txt", "retired.md", "note.md", "taste.md")}, \
        prompts, keys


# --- the happy path: three changes, one of each shape ----------------------------------------
K = ["2608.18911", "10.2139/ssrn.7309901", "2608.19389"]
CHANGES = [
    {"section": "Prefer", "op": "rewrite", "old": PREFER[1],
     "line": "- LLM and agent papers that report a walk-forward or live evaluation.",
     "argument": "Every LLM paper you thumbed up reported a walk-forward evaluation.",
     "evidence": K},
    {"section": "Reject", "op": "add", "old": "",
     "line": "- Crypto-only microstructure with no cross-asset readthrough.",
     "argument": "Five crypto microstructure papers reached the tape and you thumbed all five down.",
     "evidence": K},
    {"section": "Reject", "op": "drop", "old": DROP_REJECT, "line": "",
     "argument": "Three papers you thumbed up are exactly what this line rejects.",
     "evidence": K},
]
# Call 1 proposes; calls 2 and 3 replay the rewrite and the add. The dropped Reject line never
# reaches the judge — a rule that only pushed items down cannot demote anything by leaving.
DEMOTE = replay_scores([(i, 3 if i == 1 else 8) for i in range(1, 11)])
rc, err, out, prompts, keys = run([proposal(CHANGES), DEMOTE, replay_scores(
    [(i, 8) for i in range(1, 11)])])

check("the happy path exits 0", rc == 0, err)
body = out["pr.md"] or ""
check("only two replay passes for three changes", len(prompts) == 3, f"{len(prompts)} calls")
check("the title counts the changes and the votes",
      (out["title.txt"] or "").startswith("Taste — 3 changes from 30 votes"), out["title.txt"])

# --- the ledger ------------------------------------------------------------------------------
ledger = [l for l in body.splitlines() if re.match(r"[-*+] \[", l)]
check("one ledger line per change", len(ledger) == 3, ledger)
check("every ledger box arrives ticked", all(l.startswith("- [x] ") for l in ledger), ledger)
check("a ledger line carries no issue or PR reference",
      not any(re.search(r"#[0-9]|github\.com/[^ ]*/(issues|pull)/", l) for l in ledger), ledger)
check("the ledger shows the resulting line in italics",
      "*LLM and agent papers that report a walk-forward or live evaluation.*" in body)
check("a dropped line is shown too", "*" + DROP_REJECT[2:] + "*" in body)

# --- taste.md, and nothing else ---------------------------------------------------------------
amended = out["taste.md"].splitlines()
before = TASTE.splitlines()
added = [l for l in amended if l not in before]
removed = [l for l in before if l not in amended]
check("at most three line changes", len(added) + len(removed) <= 4,
      f"+{len(added)} -{len(removed)}")   # a rewrite is one line out and one in
check("the file stays under the hard cap", len(amended) <= 45, len(amended))
check("the amended file still validates",
      subprocess.run(["scripts/validate-taste.sh"], input=None, capture_output=True,
                     text=True).returncode == 0)
check("the header states the line count", f"goes {len(before)} → {len(amended)} lines" in body,
      [l for l in body.splitlines()[:3]])

# --- evidence: both links, every row ----------------------------------------------------------
rows = [l for l in body.splitlines() if l.startswith("| 👍 ") or l.startswith("| 👎 ")]
check("every change has an evidence table", len(rows) >= 3 * 3, len(rows))
check("each row links the paper and the vote day",
      all(re.search(r"\| \[.+\]\((https?://[^)]+)\) \| \[\d+ \w+\]\("
                    r"https://github\.com/o/r/issues/\d+\) \|$", r) for r in rows),
      rows[:2])

# --- replay is demotion-only -------------------------------------------------------------------
replays = [l for l in body.splitlines() if l.startswith("**Replayed")]
check("one replay line per change", len(replays) == 3, replays)
check("the demotion is named and scored", "(8 → 3)" in replays[0], replays[0])
check("only the demoted item is named",
      replays[0].count("→") == 1 and "8 → 8" not in replays[0], replays[0])
check("a day that shrinks is named", "drops to" in replays[0], replays[0])
check("a clean replay says nothing dropped",
      "nothing would have dropped below the bar" in replays[1], replays[1])
check("a dropped Reject line is answered without a judge pass",
      "nothing changes" in replays[2] and "next month" in replays[2], replays[2])

# --- seen, not proposed -------------------------------------------------------------------------
check("seen, not proposed is rendered",
      "## Seen, not proposed" in body and "under the 3-vote bar" in body)

# --- nothing worth proposing -----------------------------------------------------------------
rc, err, out, prompts, _ = run([proposal([], seen=["Nothing pointed the same way twice."])])
check("no changes exits 0", rc == 0, err)
check("no changes writes no PR body", out["pr.md"] is None, out["pr.md"])
check("no changes still says so", "No taste change this month" in (out["note.md"] or ""),
      out["note.md"])
check("no changes leaves taste.md alone", out["taste.md"] == TASTE)

# --- the hard rules, each one a re-roll then a dark run ---------------------------------------
def refuses(name, change, needle):
    rc, err, out, prompts, _ = run([proposal([change])])
    check(name, rc != 0 and out["pr.md"] is None and needle in err,
          f"rc={rc} err={err[-300:]}")
    check(name + ": re-rolled three times before giving up", prompts.count(prompts[0]) == 3,
          f"{len(prompts)} calls")

ok_change = dict(CHANGES[0])
refuses("a citation under the 3-vote bar is refused",
        dict(ok_change, evidence=K[:1]), "the bar is 3")
refuses("a key nobody voted on is refused",
        dict(ok_change, evidence=["2608.00000"]), "cites keys nobody voted on")
refuses("rewriting a line that is not there is refused",
        dict(ok_change, old="- A line that was never in taste.md."), "no such ## Prefer line")
refuses("an issue reference in a rule line is refused",
        dict(ok_change, line="- Papers like the one in #12."), "references an issue")
refuses("a rule line that is not a bullet is refused",
        dict(ok_change, line="Papers with a walk-forward evaluation."), "one '- ' bullet")
refuses("an add carrying an old line is refused",
        dict(ok_change, op="add"), "an add carries an `old` line")
refuses("a rewrite that changes nothing is refused",
        dict(ok_change, line=PREFER[1]), "a rewrite that changes nothing")

rc, err, out, prompts, _ = run([proposal(CHANGES + [dict(CHANGES[0], old=PREFER[0])])])
check("a fourth change is over budget", rc != 0 and "budget is 3" in err, err[-200:])

rc, err, out, prompts, _ = run([proposal([CHANGES[0], dict(CHANGES[2], section="Prefer", old=PREFER[1])])])
check("two changes to the same line are refused",
      rc != 0 and "touch the same line" in err, err[-200:])

# --- a taste PR already open --------------------------------------------------------------------
TABLE = ("- [x] **Reject, added** → *Crypto-only microstructure with no cross-asset readthrough.*\n"
         "- [x] **Prefer, added** → *Anything with a released dataset.*\n")
rc, err, out, prompts, _ = run(
    [proposal([CHANGES[0]], retired=[{"line": TABLE.splitlines()[1],
                                      "why": "the votes behind it aged out of the window"}]),
     DEMOTE],
    open_pr="Some header prose.\n\n" + TABLE)
check("the open PR's ledger reaches the judge",
      "Anything with a released dataset" in prompts[0], prompts[0][-600:])
check("the open PR's prose does not", "Some header prose" not in prompts[0])
retired = out["retired.md"] or ""
check("what came off the table is written out", "aged out of the window" in retired, retired)
check("the retirement says which rule it retired",
      "Anything with a released dataset" in retired, retired)
check("the retirement comment is not itself a checkbox",
      not re.search(r"^[-*+] \[", retired, re.M), retired)
check("the budget is per open PR, not per month", "budget is 3" not in err)

rc, err, out, prompts, _ = run(
    [proposal([CHANGES[0]], retired=[{"line": "- [x] **Prefer, added** → *Never on the table.*",
                                      "why": "invented"}]), DEMOTE],
    open_pr=TABLE)
check("retiring something never on the table is refused",
      rc != 0 and "never on the table" in err, err[-200:])

print("all propose-taste checks passed" if not fails else f"{fails} check(s) failed")
sys.exit(1 if fails else 0)
PY
