#!/usr/bin/env bash
# Self-check for fetch-arxiv.py: record shape, taste-driven query, degraded lane. SPEC.md §1.1.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import datetime, importlib.util, os, shutil, sys, tempfile

sys.path.insert(0, "scripts")   # the fetchers share lane.py
spec = importlib.util.spec_from_file_location("fa", "scripts/fetch-arxiv.py")
fa = importlib.util.module_from_spec(spec); spec.loader.exec_module(fa)

NOW_T = datetime.datetime(2026, 8, 24, 6, 0)
EMPTY = tempfile.mkdtemp()   # never the repo's candidates: a streak must not read live state

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

items = fa.parse(open("scripts/fixtures/arxiv-feed.xml", "rb").read())
check("abstract-less entry and arXiv's error feed both dropped", len(items) == 2, items)
a = items[0]
check("version suffix stripped from the key", a["key"] == "2608.18911", a["key"])
check("abs link, not pdf", a["link"] == "https://arxiv.org/abs/2608.18911", a["link"])
check("source", a["source"] == "arXiv")
check("title whitespace collapsed", a["title"] == "Investment-committee transcripts as a signal", a["title"])
check("abstract whitespace collapsed",
      a["abstract"] == "We show that transcripts carry tradable content out of sample.", a["abstract"])
check("record has exactly the five fields",
      set(a) == {"key", "source", "title", "abstract", "link"}, set(a))

with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as f:
    f.write("## Queries\n\narxiv: (cat:cs.AI AND (abs:\"one\"\n\tOR abs:\"two\"))\nssrn: x\n\n## Bar\n")
check("the arxiv line is read from taste.md, any indent continuing it",
      fa.taste_query(f.name) == '(cat:cs.AI AND (abs:"one" OR abs:"two"))', fa.taste_query(f.name))
os.unlink(f.name)

q = fa.search_query(fa.taste_query("taste.md"), datetime.datetime(2026, 8, 24, 6, 0))
check("q-fin lane unfiltered", "cat:q-fin.*" in q, q)
check("trailing 7-day window, not yesterday",
      "submittedDate:[202608170000 TO 202608242359]" in q, q)
# The whole point of rounding: a minute stamp made every run a unique URL and so a guaranteed
# cache miss at arXiv's edge, which is what was being refused. Same day, same query, or it is
# back to missing every time.
check("the window is stable across the day, so the URL can be cached",
      fa.search_query("x", datetime.datetime(2026, 8, 24, 0, 1))
      == fa.search_query("x", datetime.datetime(2026, 8, 24, 23, 59)))
check("a paper submitted an hour ago is still inside the window",
      fa.search_query("x", datetime.datetime(2026, 8, 24, 6, 0)).endswith("202608242359]"))
check("no lastUpdatedDate filter", "lastUpdatedDate" not in q)
check("https endpoint", fa.API.startswith("https://"))

# arXiv answered the runner 406 for ten days while the same URL worked through curl. The
# fallback is the only reason this lane can come back without a new vendor, so it is checked.
import urllib.error
def http(code):
    def f(*a, **k):
        raise urllib.error.HTTPError("u", code, "no", {}, None)
    return f
fa.urllib.request.urlopen = http(406)
fa.curl = lambda url: b"<feed/>"
check("a 406 retries the same URL through curl", fa.fetch("x", NOW_T) == b"<feed/>")
fa.urllib.request.urlopen = http(503)
try:
    fa.fetch("x", NOW_T); ok503 = False
except urllib.error.HTTPError:
    ok503 = True
check("any other status is not curl's problem and still raises", ok503)
def boom(url):
    raise OSError("curl exit 22: The requested URL returned error: 406")
fa.curl = boom
fa.urllib.request.urlopen = http(406)
check("curl refused too is a degraded lane, not a crash",
      fa.lane("taste.md", NOW_T, EMPTY)[1].startswith("arXiv lane unreachable: OSError"),
      fa.lane("taste.md", NOW_T, EMPTY)[1])


def down(*a):
    raise OSError("connection refused")

fa.fetch = down
items, note = fa.lane("taste.md", datetime.datetime(2026, 8, 24))
check("unreachable lane degrades to no candidates, with a note", (items, bool(note)) == ([], True), note)

fa.fetch = lambda *a: b"<<< not xml"
items, note = fa.lane("taste.md", datetime.datetime(2026, 8, 24))
check("garbage response degrades to no candidates, with a note", (items, bool(note)) == ([], True), note)

fa.fetch = lambda *a: open("scripts/fixtures/arxiv-feed.xml", "rb").read()
check("a usable lane carries no note", fa.lane("taste.md", datetime.datetime(2026, 8, 24))[1] == "")

# A blip and a ten-day outage must not read the same: the note is the only report either gets.
import json as _json
c = tempfile.mkdtemp()
def day(name, sources):
    with open(os.path.join(c, name), "w") as f:
        _json.dump([{"source": s} for s in sources], f)

fa.fetch = down
day("2026-09-19.json", ["SSRN"]); day("2026-09-18.json", ["SSRN"])
check("dead days counted off the stored candidates", fa.dead_days(c, "arXiv") == 2, fa.dead_days(c, "arXiv"))
check("the streak reaches the note, today included",
      "3 days running with no arXiv candidates" in fa.lane("taste.md", datetime.datetime(2026, 9, 20), c)[1],
      fa.lane("taste.md", datetime.datetime(2026, 9, 20), c)[1])

day("2026-09-17.json", ["arXiv", "SSRN"])   # older than the two dead days, so it cannot break them
check("a live day ends the streak rather than extending it", fa.dead_days(c, "arXiv") == 2, fa.dead_days(c, "arXiv"))
day("2026-09-19.json", ["arXiv"])
check("a live day today means no streak at all", fa.dead_days(c, "arXiv") == 0, fa.dead_days(c, "arXiv"))
check("first dead day carries the plain note, no count",
      fa.lane("taste.md", datetime.datetime(2026, 9, 20), c)[1] == "arXiv lane unreachable: OSError: connection refused",
      fa.lane("taste.md", datetime.datetime(2026, 9, 20), c)[1])
check("a missing candidates dir is not a crash", fa.dead_days(c + "/nope", "arXiv") == 0)
shutil.rmtree(c)
fa.fetch = lambda *a: open("scripts/fixtures/arxiv-feed.xml", "rb").read()   # the CLI checks below want a live lane

# The note only ever surfaces on the vote issue (§6), so the CLI has to hand it over.
d = tempfile.mkdtemp(); out, notes = d + "/f.json", d + "/notes.md"
sys.argv = ["fetch-arxiv.py", "--out", out, "--notes", notes]
fa.main()
check("a usable lane leaves no note behind", not os.path.exists(notes))
fa.fetch = down
fa.main()
check("a degraded lane leaves one note line for the vote issue",
      len(open(notes).read().strip().splitlines()) == 1, open(notes).read())
shutil.rmtree(d)

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
