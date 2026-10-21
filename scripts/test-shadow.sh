#!/usr/bin/env bash
# Self-check for the OpenRouter judge in triage.py and the shadow week in shadow.py:
# the request shape per model, fenced JSON, GONE statuses failing at once, a 5xx retrying,
# and one model's failure never skipping the next. docs/adr/0002.
# The judge is a stub OpenRouter on localhost that replays a scripted list per model.
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
     "title": "A Survey of Everything", "abstract": "A literature review.", "score": 9},
]
NEMO, GEMMA, VL, SMALL = ("nvidia/nemotron-3-super-120b-a12b:free", "google/gemma-4-31b-it:free",
                          "nvidia/nemotron-3.5-super-vl:free", "google/gemma-4-26b-a4b-it:free")

def ok(obj, fence=False):
    text = json.dumps(obj)
    return 200, {"choices": [{"message": {"content": f"```json\n{text}\n```" if fence else text}}]}

TRIAGE = ok({"scores": [{"id": 1, "score": 8, "why": "a"}, {"id": 2, "score": 3, "why": "b"}]})
CLAIM = ok({"claims": [{"id": 1, "sentence": "Execution costs fall when order books are public."}]})
PLAN = {
    NEMO: [TRIAGE] * 3 + [CLAIM],
    GEMMA: [(429, {"error": {"code": 429, "message": "rate-limited upstream"}})],
    VL: [(500, {"error": {"code": 500, "message": "boom"}}), "cut"] + [TRIAGE] * 3
        + [ok({"claims": [{"id": 1, "sentence": "Execution costs fall when order books are public."}]}, fence=True)],
    SMALL: [(200, {"error": {"code": 404, "message": "No endpoints found"}})],
}
seen = []

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
with tempfile.TemporaryDirectory() as d:
    src, dst = os.path.join(d, "c.json"), os.path.join(d, "shadow", "s.json")
    json.dump(CANDIDATES, open(src, "w"))
    env = dict(os.environ, OPENROUTER_BASE_URL=f"http://127.0.0.1:{srv.server_port}",
               OPENROUTER_API_KEY="sk-or-test")
    p = subprocess.run([sys.executable, "scripts/shadow.py", "--in", src, "--out", dst],
                       capture_output=True, text=True, env=env)
    out = json.load(open(dst)) if os.path.exists(dst) else {}
srv.shutdown()

def calls(model):
    return [b for _, _, b in seen if b["model"] == model]

check("the shadow run exits 0 whatever the models do", p.returncode == 0, p.stderr)
check("every request goes to /chat/completions with the key",
      all(path == "/chat/completions" and auth == "Bearer sk-or-test" for path, auth, _ in seen), seen[:1])
check("a full-schema model is sent the triage schema",
      calls(NEMO)[0]["response_format"]["json_schema"]["schema"]["required"] == ["scores"], calls(NEMO)[0])
check("a json_object-only model is sent json_object",
      calls(GEMMA)[0]["response_format"] == {"type": "json_object"}, calls(GEMMA)[0])
check("the system prompt and the prompt both reach the model",
      [m["role"] for m in calls(NEMO)[0]["messages"]] == ["system", "user"], calls(NEMO)[0])
check("a working model is recorded with scores by key and the claims it would publish",
      out.get(NEMO) == {"scores": {"2608.00001": 8, "2608.00002": 3},
                        "claims": {"2608.00001": "Execution costs fall when order books are public."}},
      out.get(NEMO))
check("a 429 fails at once, one request, no retry",
      len(calls(GEMMA)) == 1 and "JUDGE_DOWN" in out.get(GEMMA, {}).get("error", ""), out.get(GEMMA))
check("a 5xx and a body cut off mid-read both retry, and a fenced JSON answer is read",
      len(calls(VL)) == 6 and "claims" in out.get(VL, {}), (len(calls(VL)), out.get(VL)))
check("an error inside a 200 body is read as its code",
      "JUDGE_DOWN" in out.get(SMALL, {}).get("error", "") and "404" in out[SMALL]["error"], out.get(SMALL))
check("one model's failure never skips the next", list(out) == [NEMO, GEMMA, VL, SMALL], list(out))

sys.exit(1 if fails else 0)
PY
