#!/usr/bin/env bash
# Self-check for triage.py: the prompt, median-of-3 with the key tiebreak, reproducibility,
# the id-set mismatch, and the failure taxonomy. SPEC.md §3.1-3.2, §9.
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

CANDIDATES = [
    {"key": "2608.00002", "source": "arXiv", "title": "Order Book Execution",
     "abstract": "We  release code   and a dataset of real order book trades."},
    {"key": "2608.00001", "source": "arXiv", "title": "A Survey of Everything",
     "abstract": "A literature review of financial machine learning." + " padding" * 300},
    {"key": "10.2139/ssrn.1", "source": "SSRN", "title": "Another Price Predictor",
     "abstract": "We predict prices with no baseline and no transaction costs."},
]
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

def envelope(scores, **kw):
    e = {"type": "result", "subtype": "success", "is_error": False, "result": "done",
         "structured_output": {"scores": scores}}
    e.update(kw)
    return {"stdout": json.dumps(e)}

def score_run(triples):
    """One run's envelope: id -> score, over the key-sorted candidate order."""
    return envelope([{"id": i, "score": s, "why": f"why {i}"} for i, s in triples])

def run(plan, candidates=CANDIDATES, env=None):
    """(returncode, parsed stdout or None, stderr, prompts seen)."""
    with tempfile.TemporaryDirectory() as d:
        os.makedirs(os.path.join(d, "calls"))
        json.dump(plan, open(os.path.join(d, "plan.json"), "w"))
        with open(os.path.join(d, "claude"), "w") as f:
            f.write(STUB)
        os.chmod(os.path.join(d, "claude"), 0o755)
        e = dict(os.environ, STUB=d, PATH=d + os.pathsep + os.environ["PATH"],
                 ANTHROPIC_API_KEY="sk-should-not-reach-the-judge", **(env or {}))
        p = subprocess.run([sys.executable, "scripts/triage.py"], input=json.dumps(candidates),
                           capture_output=True, text=True, env=e)
        prompts = [open(os.path.join(d, "calls", n)).read()
                   for n in sorted(os.listdir(os.path.join(d, "calls")), key=int)]
        leaked = os.path.exists(os.path.join(d, "leaked-key"))
        try:
            out = json.loads(p.stdout)
        except ValueError:
            out = None
        return p.returncode, out, p.stderr, prompts, leaked

# Median of three: candidate order inside the prompt is by key, so ids are 1=ssrn.1,
# 2=2608.00001, 3=2608.00002.
THREE = [score_run([(1, 2), (2, 3), (3, 8)]),
         score_run([(1, 3), (2, 4), (3, 9)]),
         score_run([(1, 2), (2, 9), (3, 7)])]   # id 2 is the outlier the median removes

rc, out, err, prompts, leaked = run(THREE)
check("three runs, one call each", rc == 0 and len(prompts) == 3, (rc, len(prompts), err))
check("every candidate is stored with its score, cleared or not",
      out and len(out) == 3 and all("score" in c for c in out), out)
check("the median of the three runs wins, not the mean and not the last run",
      out and [c["score"] for c in out] == [8, 4, 2], out)
check("the why comes from the run that scored the median",
      out and out[0]["why"] == "why 3", out)
check("output is ordered score descending, then key",
      out and [c["key"] for c in out] == ["2608.00002", "2608.00001", "10.2139/ssrn.1"], out)
check("the candidate record is passed through, not rebuilt",
      out and all(c["title"] and c["link"] if "link" in c else c["title"] for c in out), out)
check("ANTHROPIC_API_KEY never reaches the judge — it would bypass the subscription", not leaked)

rc2, out2, _, _, _ = run(THREE, candidates=list(reversed(CANDIDATES)))
check("the same inputs reproduce the same scores, whatever order they arrive in",
      out == out2 and rc2 == 0, out2)

p = prompts[0]
taste = open("taste.md").read()
prefer = [l for l in taste.splitlines() if l.startswith("- ")][:5]
check("Prefer and Reject go in verbatim", all(l in p for l in prefer), p[:400])
check("the scale anchors and the hard-marker instruction are as written in SPEC.md §3.2",
      "0-2 off-topic or content-free." in p and "Be a hard marker." in p, p)
check("all three candidates are numbered into one prompt, keyed order",
      "[1] (SSRN) Another Price Predictor" in p and "[3] (arXiv) Order Book Execution" in p, p)
check("abstracts are whitespace-collapsed and shortened to 900 chars",
      "We release code and a dataset" in p and "padding padding" in p
      and max(len(l) for l in p.splitlines()) <= 900, max(len(l) for l in p.splitlines()))

# An id-set mismatch is malformed, and malformed retries.
short = score_run([(1, 2), (2, 3)])
rc, out, err, prompts, _ = run([short] + THREE)
check("a returned id set that misses a candidate is detected and retried as malformed",
      rc == 0 and len(prompts) == 4 and "id set mismatch" in err, (rc, len(prompts), err))
extra = score_run([(1, 2), (2, 3), (3, 8), (4, 9)])
rc, _, err, prompts, _ = run([extra] + THREE)
check("an id the input never carried is a mismatch too",
      rc == 0 and len(prompts) == 4 and "extra [4]" in err, (rc, len(prompts), err))

rc, _, err, prompts, _ = run([short, short, short])
check("malformed retries three times, then the day goes dark",
      rc != 0 and len(prompts) == 3 and "after 3 attempts" in err, (rc, len(prompts), err))
rc, _, err, prompts, _ = run([{"stdout": "not json at all"}] * 3)
check("an unparseable envelope is malformed, not a crash",
      rc != 0 and len(prompts) == 3 and "envelope is not JSON" in err, (rc, len(prompts), err))
rc, _, err, prompts, _ = run([{"stdout": json.dumps(
    {"type": "result", "subtype": "error_max_turns", "result": "", "is_error": True})}] * 3)
check("error_max_turns is a missing structured_output, so it retries",
      rc != 0 and len(prompts) == 3 and "no structured_output" in err, (rc, len(prompts), err))

rc, _, err, prompts, _ = run([{"exit": 124, "stdout": ""}] * 3 + THREE)
check("timeout exit 124 is a hang and retries three times",
      rc != 0 and len(prompts) == 3 and "CLI_HANG" in err, (rc, len(prompts), err))

# Auth and limits: never retry, and never branch on subtype — it still reads "success".
auth = {"stdout": json.dumps({"type": "result", "subtype": "success", "is_error": False,
                              "api_error_status": 401, "result": "done"})}
rc, _, err, prompts, _ = run([auth] + THREE)
check("a dead token fails fast, without retrying and without reading subtype",
      rc != 0 and len(prompts) == 1 and "AUTH_DEAD" in err, (rc, len(prompts), err))
oauth = {"stdout": json.dumps({"type": "result", "subtype": "success", "is_error": True,
                               "result": "OAuth token has expired, please run /login"})}
rc, _, err, prompts, _ = run([oauth] + THREE)
check("an expired-OAuth result text is AUTH_DEAD even with no api_error_status",
      rc != 0 and len(prompts) == 1 and "AUTH_DEAD" in err, (rc, len(prompts), err))
limits = {"stdout": json.dumps({"type": "result", "subtype": "success", "is_error": True,
                                "result": "5-hour limit reached, resets at 2026-09-02T14:00Z"})}
rc, _, err, prompts, _ = run([limits] + THREE)
check("an exhausted limit fails once, carrying the reset time",
      rc != 0 and len(prompts) == 1 and "LIMITS_EXHAUSTED" in err
      and "2026-09-02T14:00Z" in err, (rc, len(prompts), err))

rc, out, err, prompts, _ = run(THREE, candidates=[])
check("no candidates means no judge call and an empty file, not a failure",
      rc == 0 and out == [] and not prompts, (rc, out, err))

src = open("scripts/triage.py").read()
check("no cost or token-count logic is built on total_cost_usd or input_tokens",
      "total_cost_usd" not in src.split('"""')[2] and "input_tokens" not in src.split('"""')[2])

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
