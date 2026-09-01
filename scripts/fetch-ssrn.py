#!/usr/bin/env python3
"""The SSRN lane, via Crossref only. SPEC.md §1.2.

Nothing is ever fetched from ssrn.com — their terms forbid automated querying, and Crossref
already carries the abstract and the canonical URL we publish. Trailing 7 days on
`from-created-date`, the only usable delta key. Filtering is client-side, and its vocabulary
lives in taste.md (## Queries, the `ssrn:` line), never here. An unreachable or garbage
Crossref degrades to zero candidates and exit 0 — the day publishes from arXiv alone (§9).
"""
import argparse, datetime, html, json, os, re, sys, urllib.parse, urllib.request

API = "https://api.crossref.org/prefixes/10.2139/works"
MAILTO = os.environ.get("CROSSREF_MAILTO", "yipeng.n@gmail.com")  # polite-pool contact
UA = f"research-tape/0.1 (https://github.com/neoyipeng2018/research-tape; mailto:{MAILTO})"
WINDOW_DAYS = 7  # matches arXiv, so a skipped or degraded run self-heals tomorrow
ROWS = 1000      # a hard 400 above this
MAX_PAGES = 20   # the 10.2139 prefix runs ~7,300 records a window, so ~8 pages; the cap is
                 # here so a cursor that stops advancing ends the run rather than never
TIMEOUT = 60


def taste_terms(path):
    """The `ssrn:` line of ## Queries, indented continuations folded in, split into its two
    comma-separated term lists. Read the way fetch-arxiv.py reads its own line.

    Measured on one live 7-day window (7,278 records fetched over 8 pages):
      taste.md's arXiv `abs:"..."` phrases alone   43  ->  6.1/day
      the lists as seeded                         120  -> 17.1/day
      + bare "risk" and "tax"                     185  -> 26.4/day
    The spec's ~25/day is only reachable through that last row, and it buys diabetes-risk and
    ergonomic-risk papers, not finance ones. 17/day of on-domain candidates is the trade taken;
    widen the taste.md lists, not the judge, if a month of tapes reads thin.
    """
    line = []
    section = False
    with open(path) as f:
        for raw in f:
            if raw.startswith("## "):
                section = raw.strip() == "## Queries"
            elif section and raw.startswith("ssrn: "):
                line = [raw[len("ssrn: "):]]
            elif line and raw[:1].isspace():   # any indent continues, as validate-taste.sh reads it
                line.append(raw)
            elif line:
                break
    if not line:
        sys.exit(f"{path}: ## Queries has no 'ssrn: ' line")
    m = re.match(r"ai:(.*?)\bfinance:(.*)", " ".join(s.strip() for s in line))
    if not m:
        sys.exit(f"{path}: the 'ssrn: ' line needs an 'ai:' list and then a 'finance:' list")
    lists = [tuple(t for t in (t.strip().lower() for t in g.split(",")) if t) for g in m.groups()]
    if not all(lists):
        sys.exit(f"{path}: the 'ssrn: ' ai and finance lists must both carry terms")
    return lists


def words(terms):
    """Word-boundary, never substring: `market` as a substring drags in `marketing` and
    `supermarket`, worth 11 junk records in the measured window."""
    return re.compile(r"\b(?:" + "|".join(re.escape(t) for t in terms) + r")\b")


def clean(s):
    """Unescape until stable, then strip tags. Crossref titles are double-escaped
    (`S&amp;amp;P 500`) and abstracts are JATS-wrapped."""
    s = s or ""
    for _ in range(5):
        u = html.unescape(s)
        if u == s:
            break
        s = u
    return re.sub(r"\s+", " ", re.sub(r"<[^>]*>", " ", s)).strip()


def url(item):
    """`resource.primary.URL` — the canonical ssrn.com landing page, which we link but
    never fetch."""
    return ((item.get("resource") or {}).get("primary") or {}).get("URL", "")


def window(now):
    since = now - datetime.timedelta(days=WINDOW_DAYS)
    return f"from-created-date:{since:%Y-%m-%d},until-created-date:{now:%Y-%m-%d}"


def fetch(now, cursor):
    req = urllib.request.Request(API + "?" + urllib.parse.urlencode({
        "filter": window(now),
        "rows": ROWS,
        "cursor": cursor,   # never offset: deep paging on offset is a 400
        "select": "DOI,title,author,abstract,resource,created,type",
        "mailto": MAILTO,   # in the query string and the User-Agent both
    }), headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read())


def records(now):
    """Every record in the window, cursor-paged. A short page is the last page; a cursor
    that never exhausts stops at MAX_PAGES rather than spinning."""
    cursor = "*"
    for _ in range(MAX_PAGES):
        msg = fetch(now, cursor)["message"]
        items = msg.get("items") or []
        yield from items
        cursor = msg.get("next-cursor")
        if not cursor or len(items) < ROWS:
            return


def keep(item, ai_re, finance_re):
    """Candidate record, or None. Requiring finance in the title is what forces the paper to
    be about finance; letting AI come from the abstract is what keeps recall."""
    key, title = item.get("DOI", ""), clean((item.get("title") or [""])[0])
    abstract, link = clean(item.get("abstract")), url(item)
    # No abstract means an empty fingerprint, and §2 divides by the union.
    if not (key and title and abstract and link.startswith("https://www.ssrn.com/")):
        return None
    lt = title.lower()
    if not finance_re.search(lt) or not (ai_re.search(lt) or ai_re.search(abstract.lower())):
        return None
    return {"key": key, "source": "SSRN", "title": title, "abstract": abstract, "link": link}


def lane(taste, now):
    """(candidates, note). A dead or garbage lane degrades to no candidates and a note for the
    vote issue rather than taking the day dark. SPEC.md §9."""
    ai_re, finance_re = map(words, taste_terms(taste))  # a bad taste.md is fatal, before any fetch
    try:
        items = [c for c in (keep(r, ai_re, finance_re) for r in records(now)) if c]
    except (OSError, ValueError, KeyError) as e:  # URLError, TimeoutError, bad JSON, no message
        return [], f"Crossref lane unreachable: {e.__class__.__name__}: {e}"
    if not items:
        return [], "Crossref lane returned nothing usable"
    return items, ""


def merge(prior, items):
    """Both lanes write the same day's file, so --out appends. Keyed, because
    `workflow_dispatch` is the whole retry mechanism (§8) and a re-run would otherwise hand
    §2 two copies of every record — which its pairwise rule drops as a duplicate of itself,
    taking both."""
    seen = {c["key"] for c in prior}
    return prior + [c for c in items if c["key"] not in seen]


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--taste", default="taste.md")
    p.add_argument("--out", help="merge into this day's candidates file (default stdout)")
    a = p.parse_args()
    items, note = lane(a.taste, datetime.datetime.now(datetime.timezone.utc))
    print(note or f"ssrn: {len(items)} candidates", file=sys.stderr)
    if not a.out:
        sys.stdout.write(json.dumps(items, indent=1, ensure_ascii=False) + "\n")
        return
    prior = []
    if os.path.exists(a.out):
        with open(a.out) as f:
            prior = json.load(f)
    os.makedirs(os.path.dirname(a.out) or ".", exist_ok=True)
    with open(a.out, "w") as f:
        f.write(json.dumps(merge(prior, items), indent=1, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
