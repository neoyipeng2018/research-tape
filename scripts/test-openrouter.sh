#!/usr/bin/env bash
# Self-check for the OpenRouter judge in triage.py: the request shape per model, fenced JSON,
# GONE statuses failing at once, a 5xx and a cut-off body retrying, and the day's judge on every
# candidate. docs/adr/0002. The judge is a stub OpenRouter on localhost replaying a plan per model.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, os, subprocess, sys, tempfile, threading
from http.server import BaseHTTPRequestHandler, HTTPServer

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

CANDIDATES = [
    {"key": "2608.00001", "source": "arXiv", "link": "https://arxiv.org/abs/2608.00001",
     "title": "Order Book Execution", "abstract": "We release real order book trades."},
    {"key": "2608.00002", "source": "arXiv", "link": "https://arxiv.org/abs/2608.00002",
     "title": "A Survey of Everything", "abstract": "A literature review."},
]
VL, GEMMA, NEMO = ("nvidia/nemotron-3.5-super-vl:free", "google/gemma-4-31b-it:free",
                   "nvidia/nemotron-3-super-120b-a12b:free")
SENTENCE = "Execution costs fall when order books are public."

def ok(obj, fence=False):
    text = json.dumps(obj)
    return 200, {"choices": [{"message": {"content": f"```json\n{text}\n```" if fence else text}}]}

TRIAGE = ok({"scores": [{"id": 1, "score": 8, "why": "a"}, {"id": 2, "score": 3, "why": "b"}]})
PLAN, seen = {}, []

class Stub(BaseHTTPRequestHandler):
    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        seen.append((self.path, self.headers.get("Authorization"), body))
        r = PLAN[body["model"]].pop(0)
        status, out = (200, {}) if r == "cut" else r
        raw = json.dumps(out).encode()
        self.send_response(status)
        # "cut" promises more body than it sends: the IncompleteRead a free model produced live
        self.send_header("Content-Length", str(len(raw) + (100 if r == "cut" else 0)))
        self.end_headers()
        self.wfile.write(raw)
    def log_message(self, *a):
        pass

srv = HTTPServer(("127.0.0.1", 0), Stub)
threading.Thread(target=srv.serve_forever, daemon=True).start()
D = tempfile.mkdtemp()

def judge(model, plan, script="triage", stdin=CANDIDATES):
    """(returncode, stderr, requests this model saw) for one pass under one judge."""
    PLAN[model] = list(plan)
    before = len(seen)
    env = dict(os.environ, JUDGE=model, OPENROUTER_API_KEY="sk-or-test",
               OPENROUTER_BASE_URL=f"http://127.0.0.1:{srv.server_port}")
    args = {"triage": ["--out", f"{D}/candidates.json"],
            "claim": ["--tape-dir", f"{D}/tape", "--date", "2026-10-22"]}[script]
    p = subprocess.run([sys.executable, f"scripts/{script}.py", *args], input=json.dumps(stdin),
                       capture_output=True, text=True, env=env)
    return p.returncode, p.stderr, [b for _, _, b in seen[before:]]

rc, err, req = judge(VL, [(500, {"error": {"code": 500, "message": "boom"}}), "cut"] + [TRIAGE] * 3)
out = json.load(open(f"{D}/candidates.json")) if rc == 0 else []
check("a 5xx and a body cut off mid-read both retry", rc == 0 and len(req) == 5, (rc, len(req), err))
check("every request goes to /chat/completions with the key",
      all(path == "/chat/completions" and auth == "Bearer sk-or-test" for path, auth, _ in seen), seen[:1])
check("a full-schema model is sent the triage schema",
      req[0]["response_format"]["json_schema"]["schema"]["required"] == ["scores"], req[0])
check("the system prompt and the prompt both reach the model",
      [m["role"] for m in req[0]["messages"]] == ["system", "user"], req[0])
check("the median scores come back, and every candidate records the day's judge",
      [(c["key"], c["score"], c["judge"]) for c in out] == [("2608.00001", 8, VL), ("2608.00002", 3, VL)], out)

rc, err, req = judge(VL, [ok({"claims": [{"id": 1, "sentence": SENTENCE}]}, fence=True)], "claim", out)
tape = json.load(open(f"{D}/tape/2026-10-22.json")) if rc == 0 else {}
check("the claim pass reads a fenced JSON answer under the same judge",
      [i["claim"] for i in tape.get("items", [])] == [SENTENCE], (rc, err, tape))

rc, err, req = judge(GEMMA, [(429, {"error": {"code": 429, "message": "rate-limited upstream"}})])
check("a 429 fails the judge at once: one request, no retry, a non-zero exit",
      rc != 0 and len(req) == 1 and "JUDGE_DOWN" in err, (rc, len(req), err))
check("a json_object-only model is sent json_object", req[0]["response_format"] == {"type": "json_object"}, req[0])

rc, err, req = judge(NEMO, [(200, {"error": {"code": 404, "message": "No endpoints found"}})])
check("an error inside a 200 body is read as its code", rc != 0 and "JUDGE_DOWN" in err and "404" in err, err)

srv.shutdown()
sys.exit(1 if fails else 0)
PY
