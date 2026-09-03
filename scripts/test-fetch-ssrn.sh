#!/usr/bin/env bash
# Self-check for fetch-ssrn.py: taste.md vocabulary, record shape, client-side filter,
# escaping, paging, keyed merge, degraded lane, and the never-ssrn.com rule. SPEC.md §1.2.
set -u
cd "$(dirname "$0")/.."
python3 - <<'PY'
import datetime, importlib.util, json, os, shutil, sys, tempfile

spec = importlib.util.spec_from_file_location("fs", "scripts/fetch-ssrn.py")
fs = importlib.util.module_from_spec(spec); spec.loader.exec_module(fs)
SOURCE = open("scripts/fetch-ssrn.py").read()
AI, FINANCE = fs.taste_terms("taste.md")
AI_RE, FIN_RE = fs.words(AI), fs.words(FINANCE)
keep = lambda item: fs.keep(item, AI_RE, FIN_RE)

fails = 0
def check(name, cond, why=""):
    global fails
    print(("ok   " if cond else "FAIL ") + name + ("" if cond else f": {why}"))
    fails += 0 if cond else 1

NOW = datetime.datetime(2026, 8, 24, 6, 0)

def _taste(queries):
    p = tempfile.NamedTemporaryFile("w", suffix=".md", delete=False)
    p.write(f"# t\n\n## Queries\n\n{queries}\n\n## Prefer\n- a\n\n## Reject\n- b\n\n## Bar\nthreshold: 7\ncap: 6\n")
    p.close()
    return p.name

def _exits(f):
    try:
        f()
    except SystemExit:
        return True
    return False

PAGE = json.load(open("scripts/fixtures/crossref-works.json"))

calls = []
def one_page(now, cursor):
    calls.append(cursor)
    return PAGE

fs.fetch = one_page
items, note = fs.lane("taste.md", NOW)
check("a usable lane carries no note", note == "", note)
check("non-finance title, and the AI-less and abstract-less records, all dropped",
      len(items) == 1, [i["key"] for i in items])
a = items[0]
check("record has exactly the five fields the arXiv lane emits",
      set(a) == {"key", "source", "title", "abstract", "link"}, set(a))
check("source", a["source"] == "SSRN")
check("key is the SSRN DOI", a["key"] == "10.2139/ssrn.5100001", a["key"])
check("double-escaped title unescaped until stable",
      a["title"] == "Large Language Models and the S&P 500 Volatility Surface", a["title"])
check("JATS abstract tag-stripped and collapsed",
      a["abstract"] == "We fine-tune a transformer on option quotes and find the surface is "
                       "predictable out of sample.", a["abstract"])
check("published link is the canonical resource.primary.URL",
      a["link"] == "https://www.ssrn.com/abstract=5100001", a["link"])
check("paging starts on the wildcard cursor; a short page is the last page",
      calls == ["*"], calls)

# A full page with a live cursor must page on; one that never exhausts stops at MAX_PAGES.
full = {"message": {"next-cursor": "same",
                    "items": (PAGE["message"]["items"] * 250)[:fs.ROWS]}}
seen = []
fs.fetch = lambda now, c: (seen.append(c), full)[1]
fs.lane("taste.md", NOW)
check("a cursor that never exhausts stops at MAX_PAGES", len(seen) == fs.MAX_PAGES, len(seen))

check("both term lists are read from taste.md, and none is left in the script",
      len(AI) >= 20 and len(FINANCE) >= 60
      and not [t for t in AI + FINANCE if f'"{t}"' in SOURCE], (len(AI), len(FINANCE)))
check("a taste.md whose ssrn: line has no term lists is fatal before any fetch",
      _exits(lambda: fs.taste_terms(_taste("ssrn: AI term anywhere AND finance term in title"))))
check("a taste.md with no ssrn: line at all is fatal",
      _exits(lambda: fs.taste_terms(_taste("arxiv: cat:q-fin.*"))))
check("an empty finance list is fatal", _exits(lambda: fs.taste_terms(_taste("ssrn: ai: llm\n  finance:"))))

check("trailing 7-day window on from-created-date",
      fs.window(NOW) == "from-created-date:2026-08-17,until-created-date:2026-08-24",
      fs.window(NOW))
check("from-index-date / from-deposit-date used nowhere",
      "from-index-date" not in SOURCE and "from-deposit-date" not in SOURCE)
check("rows never exceeds 1000", fs.ROWS <= 1000, fs.ROWS)
check("the one request target is Crossref; ssrn.com is linked, never fetched",
      fs.API.startswith("https://api.crossref.org/prefixes/10.2139/works")
      and SOURCE.count("urlopen(") == 1 and "API + \"?\"" in SOURCE, fs.API)
check("mailto rides in the User-Agent as well as the query string", "mailto:" in fs.UA, fs.UA)

def one(title, abstract):
    return {"DOI": "10.2139/ssrn.9", "title": [title], "abstract": abstract,
            "resource": {"primary": {"URL": "https://www.ssrn.com/abstract=9"}}}

check("finance match is word-boundary: 'marketing' is not 'market'",
      keep(one("Deep Learning for Digital Marketing", "<jats:p>Ads.</jats:p>")) is None)
check("a finance term outside the title is not enough",
      keep(one("A Deep Learning Survey", "<jats:p>We mention the stock market once.</jats:p>"))
      is None)
check("an AI term from the abstract alone is enough",
      keep(one("Earnings Announcements and Analyst Revisions",
                  "<jats:p>We apply a large language model.</jats:p>")) is not None)
check("a non-ssrn.com primary URL is dropped",
      keep({"DOI": "10.2139/ssrn.9", "title": ["Machine Learning and Credit Risk"],
               "abstract": "<jats:p>x</jats:p>",
               "resource": {"primary": {"URL": "https://example.com/9"}}}) is None)

check("--out merges on key, so a re-run cannot duplicate a record",
      fs.merge([a], items + items) == [a], fs.merge([a], items + items))
check("--out keeps what the other lane already wrote",
      [c["source"] for c in fs.merge([{"key": "2608.1", "source": "arXiv"}], items)]
      == ["arXiv", "SSRN"])

def down(now, cursor):
    raise OSError("connection refused")

fs.fetch = down
items, note = fs.lane("taste.md", NOW)
check("unreachable lane degrades to no candidates, with a note", (items, bool(note)) == ([], True), note)

fs.fetch = lambda now, c: {"nope": 1}
items, note = fs.lane("taste.md", NOW)
check("garbage response degrades to no candidates, with a note", (items, bool(note)) == ([], True), note)

fs.fetch = lambda now, c: {"message": {"items": []}}
check("an empty result set degrades with a note",
      fs.lane("taste.md", NOW) == ([], "Crossref lane returned nothing usable"))

# A degraded lane is only ever reported on the vote issue (§6), so the CLI has to hand
# the note over. This lane fails independently of arXiv's, so it is checked independently.
d = tempfile.mkdtemp(); out, notes = d + "/f.json", d + "/notes.md"
sys.argv = ["fetch-ssrn.py", "--out", out, "--notes", notes]
fs.fetch = lambda now, c: {"message": {"items": []}}
fs.main()
check("a degraded lane leaves one note line for the vote issue",
      len(open(notes).read().strip().splitlines()) == 1, open(notes).read())
shutil.rmtree(d)

print("all ok" if not fails else f"{fails} failed")
sys.exit(1 if fails else 0)
PY
