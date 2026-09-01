#!/usr/bin/env bash
# Self-check for claim.py: the bar out of taste.md, the cap, the quiet day, the prompt's hard
# rules and their re-check on the way out, and the tape file. SPEC.md §3.3-3.4, §9.
# The judge is a stub `claude` on PATH that replays a scripted list of envelopes.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os, subprocess, sys, tempfile

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

def cand(key, score, source="arXiv"):
    return {"key": key, "source": source, "title": f"Title {key}",
            "link": f"https://example.org/{key}", "score": score,
            "why": "why", "abstract": "We  release code   and a dataset." + " padding" * 300}

# Pass 1 hands them over already in publish order: score descending, then key.
SCORED = ([cand(f"a{i}", 9) for i in range(1, 4)] + [cand(f"b{i}", 7) for i in range(1, 6)]
          + [cand("c1", 6), cand("c2", 3, "SSRN")])

STUB = r'''#!/usr/bin/env python3
import json, os, sys
d = os.environ["STUB"]
n = len(os.listdir(os.path.join(d, "calls")))
open(os.path.join(d, "calls", str(n)), "w").write(sys.stdin.read())
if "ANTHROPIC_API_KEY" in os.environ:
    open(os.path.join(d, "leaked-key"), "w").write("1")
plan = json.load(open(os.path.join(d, "plan.json")))
r = plan[min(n, len(plan) - 1)]
sys.stdout.write(r.get("stdout", ""))
sys.exit(r.get("exit", 0))
'''

def envelope(claims, **kw):
    e = {"type": "result", "subtype": "success", "is_error": False, "result": "done",
         "structured_output": {"claims": claims}}
    e.update(kw)
    return {"stdout": json.dumps(e)}

def written(n, sentence="Learned routing beats VWAP scheduling only when spreads are wide."):
    return envelope([{"id": i, "sentence": f"[{i}] {sentence}"} for i in range(1, n + 1)])

def run(plan, scored=SCORED, taste="taste.md"):
    """(returncode, the tape file or None, stderr, prompts seen)."""
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "calls"))
        json.dump(plan, open(os.path.join(d, "plan.json"), "w"))
        with open(os.path.join(d, "claude"), "w") as f:
            f.write(STUB)
        os.chmod(os.path.join(d, "claude"), 0o755)
        e = dict(os.environ, STUB=d, PATH=d + os.pathsep + os.environ["PATH"],
                 ANTHROPIC_API_KEY="sk-should-not-reach-the-judge")
        p = subprocess.run([sys.executable, "scripts/claim.py", "--date", "2026-08-19",
                            "--taste", taste, "--tape-dir", os.path.join(d, "tape")],
                           input=json.dumps(scored), capture_output=True, text=True, env=e)
        path = os.path.join(d, "tape", "2026-08-19.json")
        tape = json.load(open(path)) if os.path.exists(path) else None
        prompts = [open(os.path.join(d, "calls", n)).read()
                   for n in sorted(os.listdir(os.path.join(d, "calls")), key=int)]
        leaked = os.path.exists(os.path.join(d, "leaked-key"))
        return p.returncode, tape, p.stderr, prompts, leaked

# taste.md says threshold 7, cap 6: the three 9s and three of the five 7s, in publish order.
rc, tape, err, prompts, leaked = run([written(6)])
check("one judge call, over survivors only", rc == 0 and len(prompts) == 1, (rc, err))
check("the bar and the cap come out of taste.md",
      tape and [i["key"] for i in tape["items"]] == ["a1", "a2", "a3", "b1", "b2", "b3"], tape)
check("scanned is the whole scored set, not the published one",
      tape and tape["scanned"] == len(SCORED) and tape["date"] == "2026-08-19", tape)
check("an item is the four fields plus the key — no score, no why, no abstract",
      tape and all(set(i) == {"key", "title", "link", "source", "claim"} for i in tape["items"]),
      tape and tape["items"][:1])
check("each claim lands on its own paper",
      tape and tape["items"][2]["claim"].startswith("[3] ")
      and tape["items"][2]["title"] == "Title a3", tape and tape["items"][2])
check("ANTHROPIC_API_KEY never reaches the judge — it would bypass the subscription", not leaked)

p = prompts[0]
check("the hard rules go in as written in SPEC.md §3.3",
      "NO SEMICOLONS." in p and "One sentence, 25 words maximum." in p
      and 'Never open with "researchers"' in p and "No hype words:" in p, p[:600])
check("the sentence is asked for as a claim, not a summary",
      "It must ASSERT A CLAIM" in p and "The sentence IS the product." in p, p[:400])
check("only survivors are in the prompt, numbered, abstracts whole and collapsed",
      "[6] (arXiv) Title b3" in p and "[7] " not in p
      and "We release code and a dataset. padding" in p, p[:200])

# A tuned taste.md moves the bar without a code change.
with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
    f.write(open("taste.md").read().replace("threshold: 7", "threshold: 9").replace("cap: 6", "cap: 2"))
    tuned = f.name
rc, tape, err, prompts, _ = run([written(2)], taste=tuned)
check("a taste.md edit moves the bar and the cap, with nothing hardcoded here",
      rc == 0 and tape and [i["key"] for i in tape["items"]] == ["a1", "a2"], tape)
os.unlink(tuned)

# Thin and quiet days.
rc, tape, err, prompts, _ = run([written(1)], scored=[cand("a1", 9), cand("c1", 4)])
check("a thin day publishes under the cap, without filler",
      rc == 0 and tape and len(tape["items"]) == 1 and tape["scanned"] == 2, tape)
rc, tape, err, prompts, _ = run([written(1)], scored=[cand("c1", 6), cand("c2", 3)])
check("a day where nothing clears the bar commits an empty tape file, and calls no judge",
      rc == 0 and tape == {"date": "2026-08-19", "scanned": 2, "items": []} and not prompts,
      (rc, tape, err))
rc, tape, err, prompts, _ = run([written(1)], scored=[])
check("no candidates at all is still an empty tape, not a failure",
      rc == 0 and tape and tape["items"] == [] and not prompts, (rc, tape, err))

# The hard rules are re-read on the way out: a sentence that breaks one is malformed and retries.
def one(sentence):
    return envelope([{"id": 1, "sentence": sentence}])
ONE = [cand("a1", 9)]
for name, broken, why in [
        ("a semicolon-joined summary", "Routing beats VWAP; costs fall by 8 basis points.", "semicolon"),
        ("a sentence over 25 words", " ".join(["word"] * 26), "words"),
        ("a banned opener", "This paper shows routing beats VWAP on wide-spread days.", "banned opener"),
        ("a hype word", "Groundbreaking routing beats VWAP on wide-spread days.", "hype word"),
        ("a second sentence", "Routing beats VWAP. Costs fall by eight basis points.", "one sentence")]:
    rc, tape, err, prompts, _ = run([one(broken)] * 3, scored=ONE)
    check(f"{name} is malformed, retried, and never published",
          rc != 0 and tape is None and len(prompts) == 3 and why in err, (rc, err))

rc, tape, err, prompts, _ = run([one("Novel routing wins."), written(1)], scored=ONE)
check("a retry that comes back clean publishes",
      rc == 0 and tape and len(tape["items"]) == 1 and len(prompts) == 2, (rc, err))
rc, tape, err, prompts, _ = run([envelope([{"id": 1, "sentence": "Routing beats VWAP today."},
                                           {"id": 2, "sentence": "Extra."}])] * 3, scored=ONE)
check("an id the survivors never carried is a mismatch, retried, and no tape is written",
      rc != 0 and tape is None and "id set mismatch" in err, (rc, err))

# The failure taxonomy is pass 1's, shared: a dead token never retries.
auth = {"stdout": json.dumps({"type": "result", "subtype": "success", "is_error": False,
                              "api_error_status": 401, "result": "done"})}
rc, tape, err, prompts, _ = run([auth, written(6)])
check("a dead token fails fast and writes no tape at all",
      rc != 0 and tape is None and len(prompts) == 1 and "AUTH_DEAD" in err, (rc, err))

sys.path.insert(0, "scripts")
import claim
check("'robust' is a hype word but 'robustness' inside a longer word is not",
      claim.check("Robust routing wins.") and not claim.check("Robustness checks survive costs."))
check("an initial is not a second sentence — 'U.S.' and 'et al.' stay one claim",
      not claim.check("U.S. equities absorb the signal within a day, per Chen et al. 2026."))

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
