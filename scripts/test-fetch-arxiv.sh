#!/usr/bin/env bash
# Self-check for fetch-arxiv.py: record shape, taste-driven query, degraded lane. SPEC.md §1.1.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import datetime, importlib.util, os, sys, tempfile

spec = importlib.util.spec_from_file_location("fa", "scripts/fetch-arxiv.py")
fa = importlib.util.module_from_spec(spec); spec.loader.exec_module(fa)

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
      "submittedDate:[202608170600 TO 202608240600]" in q, q)
check("no lastUpdatedDate filter", "lastUpdatedDate" not in q)
check("https endpoint", fa.API.startswith("https://"))

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

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
