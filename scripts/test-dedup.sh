#!/usr/bin/env bash
# Self-check for dedup.py: the two real duplicate pairs, the survivor rule, the ever-published
# key, the trailing-30-day read, and pre-judge placement. SPEC.md §2.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import importlib.util, itertools, json, os, subprocess, sys, tempfile

spec = importlib.util.spec_from_file_location("dd", "scripts/dedup.py")
dd = importlib.util.module_from_spec(spec); spec.loader.exec_module(dd)

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

C = json.load(open("scripts/fixtures/candidates-dupes.json"))
by = {c["key"]: c for c in C}
def j(a, b):
    fa, fb = dd.fp(by[a]), dd.fp(by[b])
    return len(fa & fb) / len(fa | fb)

BANK_NEW, BANK_OLD = "10.2139/ssrn.7310298", "10.2139/ssrn.7303518"
FIN_ARXIV, FIN_SSRN = "2608.01234", "10.2139/ssrn.7401199"

kept = [c["key"] for c in dd.dedup(C, set(), [])]
check("the same paper under two SSRN DOIs collapses to one",
      (BANK_OLD in kept) != (BANK_NEW in kept), kept)
check("the same paper on arXiv and SSRN under different titles collapses to one",
      (FIN_ARXIV in kept) != (FIN_SSRN in kept), kept)
check("the genuine pairs all survive", len(kept) == 4, kept)
check("both duplicate pairs clear the threshold, and no genuine pair comes near it",
      min(j(BANK_NEW, BANK_OLD), j(FIN_ARXIV, FIN_SSRN)) > dd.THRESHOLD
      > max(j(a["key"], b["key"]) for a, b in itertools.combinations(C, 2)
            if {a["key"], b["key"]} not in ({BANK_NEW, BANK_OLD}, {FIN_ARXIV, FIN_SSRN})))
check("arXiv survives cross-source", FIN_ARXIV in kept and FIN_SSRN not in kept, kept)
check("same-source falls to the lower key, the earlier posting",
      BANK_OLD in kept and BANK_NEW not in kept, kept)
same_title = [{"key": "1", "source": "arXiv", "abstract": C[4]["abstract"]},
              {"key": "2", "source": "arXiv", "abstract": C[5]["abstract"]}]
for c in same_title:
    c["title"] = "Machine Learning and Asset Prices"
check("identical titles over different abstracts are two papers — title is not in the rule",
      len(dd.dedup(same_title, set(), [])) == 2)

check("an abstract-less stored record is nobody's duplicate",
      dd.same(dd.fp({"abstract": ""}), dd.fp(C[0])) is False)

# Ever-published key, cross-day fingerprint, and the day-file exclusion, through the CLI.
with tempfile.TemporaryDirectory() as d:
    tape, cand = os.path.join(d, "tape"), os.path.join(d, "candidates")
    os.makedirs(tape); os.makedirs(cand)
    def write(p, obj):
        with open(p, "w") as f:
            json.dump(obj, f)
    write(os.path.join(tape, "2019-01-02.json"),
          {"date": "2019-01-02", "scanned": 1,
           "items": [{"key": "2608.02222", "title": "t", "link": "l", "source": "arXiv",
                      "claim": "c"}]})
    write(os.path.join(cand, "2026-08-30.json"), [by[FIN_SSRN]])           # in the window
    write(os.path.join(cand, "2026-06-01.json"), [by["2608.03333"]])       # outside it
    write(os.path.join(cand, "2026-09-01.json"), C)                        # the day itself
    run = subprocess.run(
        [sys.executable, "scripts/dedup.py", "--in", "scripts/fixtures/candidates-dupes.json",
         "--tape-dir", tape, "--candidates-dir", cand, "--date", "2026-09-01"],
        capture_output=True, text=True)
    out = [c["key"] for c in json.loads(run.stdout)]
    check("a key that has ever published is dropped, at any age", "2608.02222" not in out, out)
    check("cross-day dedup reads unpublished candidates too — the arXiv copy goes as well",
          FIN_ARXIV not in out and FIN_SSRN not in out, out)
    check("a candidates file older than the 30-day window is not read", "2608.03333" in out, out)
    check("the day's own file is not read against itself", BANK_OLD in out, out)
    check("the kept and dropped counts go to stderr",
          "dedup: 2 candidates, 4 dropped" in run.stderr, run.stderr)

scored = [dict(c, score=9) for c in C[:1]]
check("dedup runs before the judge: it passes records through untouched, score or no score",
      dd.dedup(scored, set(), []) == scored and dd.dedup(C[4:5], set(), []) == C[4:5])

check("a published key is dropped before the pairwise pass, so it cannot pick the survivor",
      [c["key"] for c in dd.dedup([by[FIN_SSRN], by[FIN_ARXIV]], {FIN_ARXIV}, [])] == [FIN_SSRN])
check("the same key twice in a day collapses to one, it does not vanish",
      [c["key"] for c in dd.dedup([by[FIN_ARXIV], by[FIN_ARXIV]], set(), [])] == [FIN_ARXIV])

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
